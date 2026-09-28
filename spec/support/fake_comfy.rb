# frozen_string_literal: true

require "zlib"

# Stands in for Comfy::Client in specs: records the graphs it is sent and
# answers from a script. `finish!` marks prompts done; `fail!` makes one error.
# It has Anima installed (and whatever else `capabilities` is given).
class FakeComfy
  attr_reader :submitted, :capabilities

  def initialize(capabilities: FakeComfy.capabilities)
    @capabilities = capabilities
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

  def run_seconds(id) = (42.5 if @done.include?(id))

  def upload(bytes, name)
    (@uploads ||= []) << [ name, bytes ]
    name
  end

  def uploads = @uploads || []

  # A ComfyUI's /object_info, reduced to what the builder reads.
  def self.capabilities(checkpoints: [], diffusion_models: [ "anima-preview.safetensors" ],
                        text_encoders: [ "qwen_3_06b_base.safetensors" ], clip_types: %w[stable_diffusion sdxl anima],
                        vaes: [ "qwen_image_vae.safetensors" ], loras: [ "goblin.safetensors", "house.safetensors" ],
                        samplers: %w[euler euler_ancestral er_sde dpmpp_2m], schedulers: %w[normal karras simple sgm_uniform],
                        nodes: Comfy::Capabilities::NODES, extra: {})
    combo = ->(choices) { [ choices ] }
    info = nodes.index_with { { "input" => { "required" => {} } } }
    set = ->(node, input, choices) { info[node]["input"]["required"][input] = combo.(choices) if info[node] }
    set.("CheckpointLoaderSimple", "ckpt_name", checkpoints)
    set.("UNETLoader", "unet_name", diffusion_models)
    set.("CLIPLoader", "clip_name", text_encoders)
    set.("CLIPLoader", "type", clip_types)
    set.("VAELoader", "vae_name", vaes)
    set.("LoraLoader", "lora_name", loras)
    set.("LoraLoaderModelOnly", "lora_name", loras)
    set.("KSampler", "sampler_name", samplers)
    set.("KSampler", "scheduler", schedulers)
    Comfy::Capabilities.new(info.merge(extra))
  end

  # How two real background-removal packs describe their nodes.
  REMOVAL_NODES = {
    "InspyrenetRembg" => { "input" => { "required" => { "image" => [ "IMAGE" ], "torchscript_jit" => [ %w[default on] ] } },
                           "output" => %w[IMAGE MASK] },
    "RMBG" => { "input" => { "required" => { "image" => [ "IMAGE" ], "model" => [ [ "RMBG-2.0", "BEN2" ] ],
                                             "sensitivity" => [ "FLOAT", { "default" => 1.0 } ],
                                             "background" => [ "COMBO", { "options" => %w[Alpha Color] } ] } },
                "output" => %w[IMAGE MASK IMAGE] },
    "NeedsAModel" => { "input" => { "required" => { "model" => [ "BG_MODEL" ], "image" => [ "IMAGE" ] } }, "output" => [ "IMAGE" ] }
  }.freeze

  # A 1×1 PNG, built by hand so specs need no image library.
  def self.png
    chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
    "\x89PNG\r\n\x1A\n".b +
      chunk.("IHDR", [ 1, 1, 8, 6, 0, 0, 0 ].pack("NNCCCCC")) +
      chunk.("IDAT", Zlib::Deflate.deflate("\x00\x11\x11\x11\xFF".b)) +
      chunk.("IEND", "")
  end
end

# Pages ask what ComfyUI has installed; in specs they get FakeComfy's
# answer instead of reaching for the network.
RSpec.configure do |config|
  config.before { allow(Comfy).to receive(:capabilities).and_return(FakeComfy.capabilities) }
end
