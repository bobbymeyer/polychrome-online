# frozen_string_literal: true

require "net/http"

# ComfyUI over the network, through its plain HTTP API: queue a prompt (a
# workflow graph), ask its history whether it has finished, download the
# images it saved, and ask what it has installed. It assumes nothing about
# the machine: ComfyUI can be local, on a LAN or tailnet, or behind a proxy
# that wants a bearer token, basic auth (in the URL) or its own headers.
#
# This is the backend interface the pipeline uses; anything answering the
# same four calls can stand in for it (spec/support/fake_comfy.rb does):
#   submit(graph) → prompt id      result(prompt id) → nil or [image]
#   fetch(image)  → bytes          capabilities      → Comfy::Capabilities
module Comfy
  class Client
    NETWORK_ERRORS = [ SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError ].freeze

    def initialize(url: Comfy.config[:url], token: Comfy.config[:token], headers: Comfy.config[:headers], http: nil, timeout: 30)
      given = URI(url.to_s.chomp("/"))
      @user = given.user && URI.decode_www_form_component(given.user)
      @password = given.password && URI.decode_www_form_component(given.password)
      @base = URI(given.to_s.sub(%r{//[^@/]*@}, "//"))
      @headers = parse_headers(headers)
      @headers["Authorization"] = "Bearer #{token}" if token.present?
      @http = http
      @injected = !http.nil?
      @timeout = timeout
    end

    # The address, without any credentials in it: safe to show.
    attr_reader :base

    # Queue a graph. Returns ComfyUI's prompt id.
    def submit(graph, client_id: SecureRandom.uuid)
      body = post_json("/prompt", { prompt: graph, client_id: client_id })
      body.fetch("prompt_id") { raise Error, "ComfyUI didn't return a prompt id" }
    end

    # nil while the prompt is queued or running; otherwise the images its
    # output nodes saved, as [{ "filename", "subfolder", "type" }].
    def result(prompt_id)
      entry = get_json("/history/#{prompt_id}")[prompt_id]
      return nil unless entry

      status = entry["status"] || {}
      if status["status_str"] == "error"
        raise Error, execution_error(status) || "ComfyUI failed to run the workflow"
      end
      return nil if status.key?("completed") && !status["completed"]

      entry.fetch("outputs", {}).values.flat_map { |output| output["images"] || [] }.reject { |image| image["type"] == "temp" }
    end

    # The bytes of one saved image.
    def fetch(image)
      query = URI.encode_www_form(filename: image["filename"], subfolder: image["subfolder"].to_s, type: image["type"] || "output")
      request(Net::HTTP::Get.new(path("/view?#{query}"), @headers)).body
    end

    # What this ComfyUI has installed. Each node is asked about on its own
    # (a full /object_info can run to megabytes); a node it doesn't have
    # answers empty.
    def capabilities
      nodes = (Capabilities::NODES + BackgroundRemoval.node_names).uniq
      info = session do
        nodes.each_with_object({}) do |node, found|
          definition = get_json("/object_info/#{ERB::Util.url_encode(node)}")[node]
          found[node] = definition if definition
        end
      end
      Capabilities.new(info)
    rescue Error => e
      Capabilities.unreachable(e.message)
    rescue *NETWORK_ERRORS => e
      Capabilities.unreachable("ComfyUI isn't reachable at #{@base} (#{e.class.name.demodulize}: #{e.message})")
    end

    def reachable?
      get_json("/system_stats")
      true
    rescue Error
      false
    end

    private

    # One connection for a run of requests, when the connection is ours.
    def session
      return yield if @http

      @http = connection
      @http.start { yield }
    ensure
      @http = nil unless @injected
    end

    def parse_headers(headers)
      value = headers.is_a?(String) ? (headers.strip.empty? ? {} : JSON.parse(headers)) : headers.to_h
      value.to_h.transform_keys(&:to_s).transform_values(&:to_s)
    rescue JSON::ParserError
      raise Error, "COMFY_HEADERS isn't a JSON object"
    end

    def execution_error(status)
      message = Array(status["messages"]).find { |kind, _| kind == "execution_error" }&.last
      message && [ message["node_type"], message["exception_message"] ].compact.join(": ").strip.presence
    end

    def get_json(path)
      parse(request(Net::HTTP::Get.new(path(path), @headers)))
    end

    def post_json(path, payload)
      req = Net::HTTP::Post.new(path(path), @headers.merge("Content-Type" => "application/json"))
      req.body = JSON.generate(payload)
      parse(request(req))
    end

    def path(path)
      "#{@base.path}#{path}"
    end

    def request(req)
      req.basic_auth(@user, @password.to_s) if @user
      response = (@http || connection).request(req)
      return response if response.is_a?(Net::HTTPSuccess)

      raise Error, rejection(response)
    rescue *NETWORK_ERRORS => e
      raise Error, "ComfyUI isn't reachable at #{@base} (#{e.class.name.demodulize}: #{e.message})"
    end

    # ComfyUI explains a rejected graph in "error" and per-node "node_errors".
    def rejection(response)
      body = JSON.parse(response.body.to_s) rescue {}
      nodes = (body["node_errors"] || {}).values.flat_map do |node|
        Array(node["errors"]).map { |e| "#{node['class_type']}: #{e['details'].presence || e['message']}" }
      end
      [ body.dig("error", "message") || "ComfyUI answered #{response.code}", *nodes ].join(" · ")
    end

    def parse(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      raise Error, "ComfyUI sent something that isn't JSON"
    end

    def connection
      Net::HTTP.new(@base.host, @base.port).tap do |http|
        http.use_ssl = @base.scheme == "https"
        http.open_timeout = [ @timeout, 5 ].min
        http.read_timeout = @timeout
      end
    end
  end
end
