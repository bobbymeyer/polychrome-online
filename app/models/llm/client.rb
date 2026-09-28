# frozen_string_literal: true

require "net/http"

# A language model over the network, through the OpenAI-compatible
# /chat/completions call that llama.cpp, llama-swap, Ollama, LM Studio, vLLM
# and hosted APIs all answer. Nothing here assumes which one.
#
# The interface the app uses; anything answering it can stand in:
#   chat(system:, user:) → the reply's text
#   json(system:, user:) → the reply parsed as a JSON object
module Llm
  class Client
    NETWORK_ERRORS = [ SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError ].freeze

    def initialize(url: Llm.config[:url], model: Llm.config[:model], token: Llm.config[:token],
                   headers: Llm.config[:headers], timeout: Llm.config[:timeout], http: nil)
      given = URI(url.to_s.chomp("/"))
      @user = given.user && URI.decode_www_form_component(given.user)
      @password = given.password && URI.decode_www_form_component(given.password)
      @base = URI(given.to_s.sub(%r{//[^@/]*@}, "//"))
      @model = model.to_s
      @headers = parse_headers(headers).merge("Content-Type" => "application/json")
      @headers["Authorization"] = "Bearer #{token}" if token.present?
      @timeout = timeout.to_i.positive? ? timeout.to_i : 120
      @http = http
    end

    # A reply that is JSON, parsed. Local models wrap it in prose or code
    # fences often enough that the first object in the reply is taken; if
    # there's none, they're asked once more, plainly.
    def json(system:, user:, temperature: 0.7, max_tokens: 1500)
      reply = chat(system: system, user: user, temperature: temperature, max_tokens: max_tokens)
      Llm.parse_json(reply) || Llm.parse_json(chat(system: system, temperature: temperature, max_tokens: max_tokens,
                                                   user: "#{user}\n\nReply with one JSON object and nothing else.")) ||
        raise(Error, "The language model didn't answer in JSON")
    end

    # One exchange. Reasoning models' <think> blocks are left out of the reply.
    def chat(system:, user:, temperature: 0.3, max_tokens: 400)
      payload = { messages: [ { role: "system", content: system }, { role: "user", content: user } ],
                  temperature: temperature, max_tokens: max_tokens, stream: false }
      payload[:model] = @model if @model.present?
      req = Net::HTTP::Post.new("#{@base.path}/chat/completions", @headers)
      req.body = JSON.generate(payload)
      body = parse(request(req))
      text = body.dig("choices", 0, "message", "content").to_s
      text = text.gsub(%r{<think>.*?</think>}m, "").strip
      raise Error, "The language model sent an empty reply" if text.empty?

      text
    end

    private

    def request(req)
      req.basic_auth(@user, @password.to_s) if @user
      response = connection.request(req)
      return response if response.is_a?(Net::HTTPSuccess)

      detail = (JSON.parse(response.body.to_s).dig("error", "message") rescue nil)
      raise Error, [ "The language model answered #{response.code}", detail ].compact.join(": ")
    rescue *NETWORK_ERRORS => e
      raise Error, "The language model isn't reachable at #{@base} (#{e.class.name.demodulize})"
    end

    def parse(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      raise Error, "The language model sent something that isn't JSON"
    end

    def parse_headers(headers)
      value = headers.is_a?(String) ? (headers.strip.empty? ? {} : JSON.parse(headers)) : headers.to_h
      value.to_h.transform_keys(&:to_s).transform_values(&:to_s)
    rescue JSON::ParserError
      raise Error, "LLM_HEADERS isn't a JSON object"
    end

    def connection
      @http || Net::HTTP.new(@base.host, @base.port).tap do |http|
        http.use_ssl = @base.scheme == "https"
        http.open_timeout = [ @timeout, 10 ].min
        http.read_timeout = @timeout
      end
    end
  end
end
