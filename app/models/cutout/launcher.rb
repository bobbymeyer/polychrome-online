# frozen_string_literal: true

require "net/http"

# The background remover, started by the app itself (hardwired): when the
# address is this machine's (the default, http://127.0.0.1:7071) and the
# remover isn't answering there, the first picture that needs cutting out
# starts `bin/cutout` (which installs rembg and fetches the model the first
# time), waits a little for it to come up, and otherwise says it isn't
# reachable yet, so the batch waits and tries again
# (ApplicationJob.waits_for_services) rather than failing. Nothing to set:
# no address on the Settings page, no CUTOUT_URL. From a container the
# remover is on the host, which the app can't start: run bin/cutout there.
#
# "Answering" means the remover answering (rembg's /api page), not just
# something listening on the port: on a Mac, AirPlay Receiver holds port 7000 and
# turns every picture down. Something else on the port is said so, rather
# than sent pictures.
module Cutout
  class Launcher
    LOCAL_HOSTS = %w[127.0.0.1 localhost ::1 0.0.0.0].freeze
    PID_FILE = "tmp/pids/cutout.pid"
    LOG_FILE = "log/cutout.log"
    # How long one picture waits for the server to come up before its
    # batch is told to try again later: a warm start takes seconds; the
    # first ever start (installing, fetching the model) takes minutes.
    BOOT = 60

    @lock = Mutex.new
    @started = nil

    class << self
      # The address is on this machine, so the app could start it.
      def local?(url)
        uri = URI(url.to_s)
        LOCAL_HOSTS.include?(uri.host.to_s)
      rescue URI::InvalidURIError
        false
      end

      def wanted?(config = Cutout.config)
        config[:url].present? && config[:autostart] != false && config[:autostart].to_s != "0" && local?(config[:url])
      end

      # Start the remover if it should be here and isn't. Returns true when
      # it is answering (already, or now), raises Cutout::Unreachable when
      # it isn't yet, and Cutout::Error when something else holds the port.
      # probe: what answers at the address (#probe).
      def ensure_running!(config: Cutout.config, spawner: Process.method(:spawn), probe: method(:probe), wait: BOOT, sleeper: method(:sleep))
        return true unless wanted?(config)

        uri = URI(config[:url])
        case probe.call(uri)
        when :remover then return true
        when :other then raise Cutout::Error, taken(uri)
        end

        @lock.synchronize { start!(uri.port, spawner) unless starting? }
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
        until (answer = probe.call(uri)) == :remover
          # Ours is starting, so something else got there first.
          raise Cutout::Error, taken(uri) if answer == :other && !starting?
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            raise Cutout::Unreachable, "The background remover is starting at #{uri.host}:#{uri.port} (bin/cutout, see #{LOG_FILE}); " \
                                       "the first start installs it and fetches the model, so this will carry on when it's up"
          end
          sleeper.call(1)
        end
        true
      end

      # What answers at the address: :remover (rembg's /api page, or a
      # stand-in's that answers it too), :other
      # (something listening that isn't it) or :none.
      def probe(uri)
        response = Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 3) { |http| http.get("/api") }
        response.is_a?(Net::HTTPSuccess) ? :remover : :other
      rescue SystemCallError, IOError, Timeout::Error, SocketError
        :none
      rescue Net::HTTPBadResponse, Net::ProtocolError
        :other
      end

      def taken(uri)
        "Something other than the background remover answers at #{uri.host}:#{uri.port} " \
          "(on a Mac, port 7000 is AirPlay Receiver's): free the port, or run bin/cutout on another (CUTOUT_PORT) and point CUTOUT_URL at it"
      end

      # A bin/cutout this app started (or another process did) that is still alive.
      def starting?
        pid = File.read(Rails.root.join(PID_FILE)).to_i
        pid.positive? && Process.kill(0, pid) && true
      rescue Errno::ENOENT, Errno::ESRCH, Errno::EPERM
        false
      end

      def start!(port, spawner)
        FileUtils.mkdir_p(Rails.root.join("tmp/pids"))
        log = File.open(Rails.root.join(LOG_FILE), "a")
        pid = spawner.call({ "CUTOUT_PORT" => port.to_s }, Rails.root.join("bin/cutout").to_s, out: log, err: log, pgroup: true, chdir: Rails.root.to_s)
        log.close
        File.write(Rails.root.join(PID_FILE), pid.to_s)
        Process.detach(pid)
        @started = pid
        Rails.logger.info("Started the background remover (bin/cutout, pid #{pid}) on port #{port}")
        at_exit { stop! } unless @hooked
        @hooked = true
        pid
      end

      # Take down what this process started, when it goes.
      def stop!
        return unless @started

        Process.kill("TERM", -@started) rescue Process.kill("TERM", @started) rescue nil
        @started = nil
      end
    end
  end
end
