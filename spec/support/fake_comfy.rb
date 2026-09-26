# frozen_string_literal: true

require "zlib"

# Stands in for Comfy::Client in specs: records the graphs it is sent and
# answers from a script. `finish!` marks prompts done; `fail!` makes one error.
class FakeComfy
  attr_reader :submitted

  def initialize
    @submitted = []
    @done = []
    @failed = {}
  end

  def submit(graph)
    @submitted << graph
    "prompt-#{@submitted.size}"
  end

  def finish!(*ids) = @done.concat(ids)
  def fail!(id, message) = @failed[id] = message

  def result(id)
    raise Comfy::Error, @failed[id] if @failed.key?(id)
    return nil unless @done.include?(id)

    [ { "filename" => "#{id}.png", "subfolder" => "polychrome", "type" => "output" } ]
  end

  def fetch(_image) = FakeComfy.png

  # A 1×1 PNG, built by hand so specs need no image library.
  def self.png
    chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
    "\x89PNG\r\n\x1A\n".b +
      chunk.("IHDR", [ 1, 1, 8, 6, 0, 0, 0 ].pack("NNCCCCC")) +
      chunk.("IDAT", Zlib::Deflate.deflate("\x00\x11\x11\x11\xFF".b)) +
      chunk.("IEND", "")
  end
end
