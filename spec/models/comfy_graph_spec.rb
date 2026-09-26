# frozen_string_literal: true

require "rails_helper"

RSpec.describe Comfy::Graph do
  let(:recipe) do
    { "checkpoint" => "base.safetensors", "loras" => [], "positive" => "a goblin", "negative" => "text",
      "width" => 832, "height" => 1216, "transparent" => true }
  end

  def build(overrides = {}, settings: {})
    described_class.build(recipe.merge(overrides), seed: 42, prefix: "polychrome/goblin-42", settings: settings)
  end

  def nodes(graph, type) = graph.select { |_, node| node["class_type"] == type }

  it "wires the checkpoint straight into the prompts and sampler when there are no LoRAs" do
    graph = build
    checkpoint = nodes(graph, "CheckpointLoaderSimple").keys.sole
    sampler = nodes(graph, "KSampler").values.sole["inputs"]
    expect(nodes(graph, "LoraLoader")).to be_empty
    expect(sampler).to include("seed" => 42, "model" => [ checkpoint, 0 ])
    expect(nodes(graph, "CLIPTextEncode").values.map { |n| n["inputs"]["text"] }).to eq([ "a goblin", "text" ])
    expect(nodes(graph, "CLIPTextEncode").values.map { |n| n["inputs"]["clip"] }.uniq).to eq([ [ checkpoint, 1 ] ])
    expect(nodes(graph, "EmptyLatentImage").values.sole["inputs"]).to include("width" => 832, "height" => 1216, "batch_size" => 1)
    expect(nodes(graph, "SaveImage").values.sole["inputs"]["filename_prefix"]).to eq("polychrome/goblin-42")
  end

  it "chains one LoraLoader per LoRA, in order, and feeds the last one onward" do
    graph = build({ "loras" => [ { "name" => "house.safetensors", "strength" => 0.8 }, { "name" => "goblin.safetensors", "strength" => 1.2 } ] })
    first, second = nodes(graph, "LoraLoader").to_a
    checkpoint = nodes(graph, "CheckpointLoaderSimple").keys.sole
    expect(first.last["inputs"]).to include("lora_name" => "house.safetensors", "strength_model" => 0.8, "model" => [ checkpoint, 0 ], "clip" => [ checkpoint, 1 ])
    expect(second.last["inputs"]).to include("lora_name" => "goblin.safetensors", "strength_clip" => 1.2, "model" => [ first.first, 0 ])
    expect(nodes(graph, "KSampler").values.sole["inputs"]["model"]).to eq([ second.first, 0 ])
    expect(nodes(graph, "CLIPTextEncode").values.map { |n| n["inputs"]["clip"] }.uniq).to eq([ [ second.first, 1 ] ])
  end

  it "puts the background-removal node before SaveImage only when asked for and configured" do
    expect(nodes(build, "Rembg")).to be_empty

    graph = build(settings: { "rembg_node" => "Rembg", "rembg_input" => "images" })
    rembg_id, rembg = nodes(graph, "Rembg").sole
    decode = nodes(graph, "VAEDecode").keys.sole
    expect(rembg["inputs"]).to eq("images" => [ decode, 0 ])
    expect(nodes(graph, "SaveImage").values.sole["inputs"]["images"]).to eq([ rembg_id, 0 ])

    expect(nodes(build({ "transparent" => false }, settings: { "rembg_node" => "Rembg" }), "Rembg")).to be_empty
  end

  it "only refers to nodes that exist" do
    graph = build({ "loras" => [ { "name" => "a", "strength" => 1 } ] }, settings: { "rembg_node" => "Rembg" })
    refs = graph.values.flat_map { |node| node["inputs"].values.select { |v| v.is_a?(Array) } }
    expect(refs.map(&:first) - graph.keys).to be_empty
  end
end
