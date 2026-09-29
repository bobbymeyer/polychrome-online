# frozen_string_literal: true

# The background-removal service over HTTP (config/cutout.yml): the image
# goes up as a multipart `file`, with the model as `model`, and a PNG comes
# back. That's rembg's API (`rembg s`); anything answering the same way can
# stand in (spec/support/fake_cutout.rb does).
module Cutout
  class Client
    def initialize(url: Cutout.config[:url], path: Cutout.config[:path], model: Cutout.config[:model],
                   token: Cutout.config[:token], timeout: Cutout.config[:timeout], http: nil)
      @path = path.presence || "/api/remove"
      @model = model.presence
      @remote = Remote::Connection.new(service: Cutout, name: "The background remover", url: url, token: token,
                                       timeout: timeout.to_i.positive? ? timeout.to_i : 120,
                                       rejection: ->(response) { "The background remover answered #{response.code}: #{response.body.to_s.truncate(200)}" },
                                       http: http)
    end

    # PNG bytes in, the cut-out PNG back.
    def remove(bytes)
      fields = [ [ "file", StringIO.new(bytes), { filename: "image.png", content_type: "image/png" } ] ]
      fields << [ "model", @model ] if @model
      body = @remote.post_form(@path, fields).body
      raise Error, "The background remover sent back something that isn't a PNG" unless body.to_s.b.start_with?("\x89PNG".b)

      body
    end
  end
end
