# frozen_string_literal: true

require "net/http"

# The background-removal service over HTTP (config/cutout.yml): the image
# goes up as a multipart `file`, with the model as `model`, and a PNG comes
# back. That's rembg's API (`rembg s`); anything answering the same way can
# stand in (spec/support/fake_cutout.rb does).
module Cutout
  class Client
    NETWORK_ERRORS = [ SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError ].freeze

    def initialize(url: Cutout.config[:url], path: Cutout.config[:path], model: Cutout.config[:model],
                   token: Cutout.config[:token], timeout: Cutout.config[:timeout], http: nil)
      @base = URI(url.to_s.chomp("/"))
      @path = path.presence || "/api/remove"
      @model = model.presence
      @token = token.presence
      @timeout = timeout.to_i.positive? ? timeout.to_i : 120
      @http = http
    end

    # PNG bytes in, the cut-out PNG back.
    def remove(bytes)
      req = Net::HTTP::Post.new("#{@base.path}#{@path}")
      req["Authorization"] = "Bearer #{@token}" if @token
      fields = [ [ "file", StringIO.new(bytes), { filename: "image.png", content_type: "image/png" } ] ]
      fields << [ "model", @model ] if @model
      req.set_form(fields, "multipart/form-data")
      response = (@http || connection).request(req)
      raise Error, "The background remover answered #{response.code}: #{response.body.to_s.truncate(200)}" unless response.is_a?(Net::HTTPSuccess)
      raise Error, "The background remover sent back something that isn't a PNG" unless response.body.to_s.b.start_with?("\x89PNG".b)

      response.body
    rescue *NETWORK_ERRORS => e
      raise Unreachable, "The background remover isn't reachable at #{@base} (#{e.class.name.demodulize}: #{e.message})"
    end

    private

    def connection
      Net::HTTP.new(@base.host, @base.port).tap do |http|
        http.use_ssl = @base.scheme == "https"
        http.open_timeout = [ @timeout, 5 ].min
        http.read_timeout = @timeout
      end
    end
  end
end
