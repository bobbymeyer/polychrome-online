# frozen_string_literal: true

require "net/http"

# A thin client for ComfyUI's HTTP API: queue a prompt (a workflow graph),
# ask its history whether it has finished, download the images it saved, and
# list the checkpoints and LoRAs it has installed.
module Comfy
  class Client
    def initialize(url: Comfy.config[:url], http: nil, timeout: 30)
      @base = URI(url.to_s.chomp("/"))
      @http = http
      @timeout = timeout
    end

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
      request(Net::HTTP::Get.new(path("/view?#{query}"))).body
    end

    # What ComfyUI has installed, for the pickers. Empty if it can't be reached.
    def checkpoints
      choices("CheckpointLoaderSimple", "ckpt_name")
    end

    def loras
      choices("LoraLoader", "lora_name")
    end

    def reachable?
      get_json("/system_stats")
      true
    rescue Error
      false
    end

    private

    def choices(node, input)
      info = get_json("/object_info/#{node}")
      Array(info.dig(node, "input", "required", input, 0))
    rescue Error
      []
    end

    def execution_error(status)
      message = Array(status["messages"]).find { |kind, _| kind == "execution_error" }&.last
      message && [ message["node_type"], message["exception_message"] ].compact.join(": ").strip.presence
    end

    def get_json(path)
      parse(request(Net::HTTP::Get.new(path(path))))
    end

    def post_json(path, payload)
      req = Net::HTTP::Post.new(path(path), "Content-Type" => "application/json")
      req.body = JSON.generate(payload)
      parse(request(req))
    end

    def path(path)
      "#{@base.path}#{path}"
    end

    def request(req)
      response = connection.request(req)
      return response if response.is_a?(Net::HTTPSuccess)

      raise Error, rejection(response)
    rescue SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise Error, "ComfyUI isn't reachable at #{@base} (#{e.class.name.demodulize})"
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
      @http || Net::HTTP.new(@base.host, @base.port).tap do |http|
        http.use_ssl = @base.scheme == "https"
        http.open_timeout = [ @timeout, 5 ].min
        http.read_timeout = @timeout
      end
    end
  end
end
