# frozen_string_literal: true

require "rails_helper"

RSpec.describe Comfy::Workflow do
  let(:recipe) do
    { "model" => "anima-preview.safetensors", "family" => "anima", "loras" => [], "positive" => "a goblin",
      "negative" => "text", "width" => 1024, "height" => 1024, "transparent" => false }
  end
  let(:caps) { FakeComfy.capabilities }

  def build(overrides = {}, capabilities: caps)
    described_class.build(recipe.merge(overrides), seed: 42, prefix: "polychrome/goblin-42", capabilities: capabilities)
  end

  def nodes(graph, type) = graph.select { |_, node| node["class_type"] == type }
  def sole(graph, type) = nodes(graph, type).values.sole["inputs"]

  it "loads a bare diffusion model with the text encoder and VAE its family needs, found on the server" do
    graph = build
    expect(sole(graph, "UNETLoader")).to include("unet_name" => "anima-preview.safetensors")
    expect(sole(graph, "CLIPLoader")).to eq("clip_name" => "qwen_3_06b_base.safetensors", "type" => "anima")
    expect(sole(graph, "VAELoader")).to eq("vae_name" => "qwen_image_vae.safetensors")
    expect(nodes(graph, "CheckpointLoaderSimple")).to be_empty
    expect(sole(graph, "KSampler")).to include("seed" => 42, "steps" => 30, "cfg" => 4.5, "sampler_name" => "er_sde", "scheduler" => "simple")
    expect(described_class.outline(graph)).to eq(
      "UNETLoader → CLIPLoader → VAELoader → CLIPTextEncode ×2 → EmptyLatentImage → KSampler → VAEDecode → SaveImage"
    )
  end

  it "takes the family's next choice when the server lacks the first" do
    older = FakeComfy.capabilities(clip_types: %w[stable_diffusion sdxl], samplers: %w[euler euler_ancestral])
    graph = build(capabilities: older)
    expect(sole(graph, "CLIPLoader")["type"]).to eq("stable_diffusion")
    expect(sole(graph, "KSampler")["sampler_name"]).to eq("euler_ancestral")
  end

  it "stacks LoRAs in order on the model alone, leaving out switched-off ones" do
    loras = [ { "name" => "house.safetensors", "strength" => 0.8, "on" => true },
              { "name" => "nope.safetensors", "strength" => 1.0, "on" => false },
              { "name" => "goblin.safetensors", "strength" => 0.5, "on" => true } ]
    graph = build({ "loras" => loras })
    chain = nodes(graph, "LoraLoaderModelOnly").values.map { |n| n["inputs"] }
    expect(chain.map { |l| [ l["lora_name"], l["strength_model"] ] }).to eq([ [ "house.safetensors", 0.8 ], [ "goblin.safetensors", 0.5 ] ])
    unet = nodes(graph, "UNETLoader").keys.sole
    expect(chain.first["model"]).to eq([ unet, 0 ])
    expect(sole(graph, "KSampler")["model"]).to eq([ nodes(graph, "LoraLoaderModelOnly").keys.last, 0 ])
    expect(nodes(graph, "LoraLoader")).to be_empty
  end

  it "skips the negative encode entirely when cfg is 1 (a turbo model ignores it)" do
    turbo = FakeComfy.capabilities(diffusion_models: [ "krea2_turbo_bf16.safetensors" ], text_encoders: [ "qwen3vl_4b_bf16.safetensors" ],
                                   clip_types: %w[stable_diffusion krea2])
    graph = build({ "model" => "krea2_turbo_bf16.safetensors", "family" => "krea2" }, capabilities: turbo)
    expect(sole(graph, "CLIPLoader")).to eq("clip_name" => "qwen3vl_4b_bf16.safetensors", "type" => "krea2")
    expect(nodes(graph, "CLIPTextEncode").size).to eq(1)
    positive = nodes(graph, "CLIPTextEncode").keys.sole
    zero = nodes(graph, "ConditioningZeroOut")
    expect(zero.values.sole["inputs"]).to eq("conditioning" => [ positive, 0 ])
    expect(sole(graph, "KSampler")).to include("steps" => 8, "cfg" => 1.0, "negative" => [ zero.keys.sole, 0 ])
  end

  it "loads a checkpoint in one node, with LoRAs on model and text encoder, and CLIP skip for Pony" do
    sdxl = FakeComfy.capabilities(checkpoints: [ "SDXL/ponyDiffusionV6XL.safetensors" ])
    graph = build({ "model" => "ponyDiffusionV6XL.safetensors", "family" => "sdxl",
                    "loras" => [ { "name" => "goblin.safetensors", "strength" => 0.6, "on" => true } ] }, capabilities: sdxl)
    checkpoint = nodes(graph, "CheckpointLoaderSimple").keys.sole
    expect(sole(graph, "CheckpointLoaderSimple")).to eq("ckpt_name" => "SDXL/ponyDiffusionV6XL.safetensors")
    expect(sole(graph, "LoraLoader")).to include("model" => [ checkpoint, 0 ], "clip" => [ checkpoint, 1 ], "strength_clip" => 0.6)
    expect(sole(graph, "CLIPSetLastLayer")).to include("stop_at_clip_layer" => -2)
    expect(sole(graph, "VAEDecode")["vae"]).to eq([ checkpoint, 2 ])
    expect(nodes(graph, "UNETLoader")).to be_empty
  end

  it "says what's missing instead of sending a graph ComfyUI would reject" do
    expect { build({ "model" => "nothing.safetensors" }) }.to raise_error(Comfy::Error, /nothing.safetensors isn't on ComfyUI/)
    expect { build({ "loras" => [ { "name" => "gone.safetensors", "strength" => 1, "on" => true } ] }) }
      .to raise_error(Comfy::Error, /LoRA gone.safetensors isn't on ComfyUI/)
    expect { build(capabilities: FakeComfy.capabilities(text_encoders: [])) }.to raise_error(Comfy::Error, /Anima needs its text encoder/)
  end

  it "removes the background only when asked and the node is installed" do
    allow(Comfy).to receive(:config).and_return(Comfy.config.merge(rembg_node: "Image Remove Background (rembg)"))
    expect(nodes(build({ "transparent" => true }), "Image Remove Background (rembg)")).to be_empty
    with_rembg = FakeComfy.capabilities(nodes: Comfy::Capabilities::NODES + [ "Image Remove Background (rembg)" ])
    graph = build({ "transparent" => true }, capabilities: with_rembg)
    rembg = nodes(graph, "Image Remove Background (rembg)").keys.sole
    expect(sole(graph, "SaveImage")["images"]).to eq([ rembg, 0 ])
  end

  describe Comfy::Family do
    it "picks a family by the model's name, with its variants laid over" do
      expect(described_class.for("anima-preview.safetensors").slug).to eq("anima")
      turbo = described_class.for("krea2_turbo_bf16.safetensors")
      expect([ turbo.slug, turbo.steps, turbo.cfg, turbo.negative? ]).to eq([ "krea2", 8, 1.0, false ])
      raw = described_class.for("krea2_raw_bf16.safetensors")
      expect([ raw.steps, raw.negative? ]).to eq([ 52, true ])
      pony = described_class.for("ponyDiffusionV6XL.safetensors")
      expect([ pony.slug, pony.label, pony.clip_skip, pony.prompt_style ]).to eq([ "sdxl", "Pony", 2, "tags" ])
    end

    it "goes by where an unknown name is stored: a checkpoint is SDXL, anything else the default" do
      caps = FakeComfy.capabilities(checkpoints: [ "mystery.safetensors" ])
      expect(described_class.for("mystery.safetensors", capabilities: caps).slug).to eq("sdxl")
      expect(described_class.for("other.safetensors", capabilities: -> { caps }).slug).to eq("anima")
    end

    it "scales a size into the trained range, keeping its shape" do
      anima = described_class.for("anima-preview.safetensors")
      expect(anima.size(512, 512)).to eq([ 896, 896 ])
      expect(anima.size(832, 1216)).to eq([ 832, 1216 ])
      expect(anima.size(2048, 2048)).to eq([ 1136, 1136 ])
      expect(described_class.for("krea2_turbo.safetensors").size(832, 1216)).to eq([ 848, 1248 ])
    end
  end
end
