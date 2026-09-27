# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe "Composing an image recipe (§8)" do
  describe ArtDirection do
    it "cleans LoRA rows from a form: blanks dropped, strength a float, 1.0 by default, on unless switched off" do
      rows = { "0" => { "name" => " house.safetensors ", "strength" => "0.75", "on" => "1" }, "1" => { "name" => "hero", "strength" => "", "on" => "0" },
               "2" => { "name" => "" } }
      expect(described_class.loras(rows)).to eq([ { "name" => "house.safetensors", "strength" => 0.75, "on" => true },
                                                  { "name" => "hero", "strength" => 1.0, "on" => false } ])
      expect(described_class.loras([ { name: "x", strength: 99 } ])).to eq([ { "name" => "x", "strength" => 5.0, "on" => true } ])
    end

    it "stacks LoRAs in layer order: a later layer naming one again changes it in place, or switches it off" do
      world = [ { "name" => "house", "strength" => 0.8 }, { "name" => "grain", "strength" => 0.3 } ]
      type = [ { "name" => "profile", "strength" => 1 } ]
      entry = [ { "name" => "house", "strength" => 0.4 }, { "name" => "grain", "strength" => 0.3, "on" => false } ]
      stack = described_class.stack_loras(world, type, entry)
      expect(stack.map { |l| [ l["name"], l["strength"], l["on"] ] }).to eq([ [ "house", 0.4, true ], [ "grain", 0.3, false ], [ "profile", 1.0, true ] ])
      expect(described_class.active_loras(stack).map { |l| l["name"] }).to eq(%w[house profile])
    end

    it "takes the model from the lowest layer that names one" do
      expect(described_class.pick_model("", "type.safetensors", "world.safetensors", "default.safetensors")).to eq("type.safetensors")
      expect(described_class.pick_model(nil, " ", nil, "default.safetensors")).to eq("default.safetensors")
    end

    it "joins prompt parts, skipping blanks and doubled commas" do
      expect(described_class.join_prompt("pixel art,", nil, " ", "full body", "Goblin")).to eq("pixel art, full body, Goblin")
    end
  end

  describe "an entry's recipe" do
    let!(:world) { Seeds::BaseWorld.run }
    let(:goblin) { world.monsters.find_by!(slug: "goblin") }

    it "starts from config defaults for the content type" do
      type = world.art_type("monster")
      expect(type).to be_persisted
      expect(type.prompt).to include("profile view")
      expect(world.art_type("monster")).to eq(type)
    end

    it "composes world style, then type framing, then the entry, with the family's words first and every layer's LoRAs" do
      world.update!(art_style: "16-bit pixel art", art_negative: "photo", art_model: "pixelXL.safetensors",
                    art_loras: [ { "name" => "house", "strength" => 0.8 } ])
      world.art_type("monster").update!(prompt: "profile view, full body", negative: "cropped", width: 768, height: 768,
                                        model: "ponyDiffusionV6XL.safetensors", loras: [ { "name" => "sprites", "strength" => 1 } ])
      goblin.update!(art_notes: "green skin, a rusty knife", art_loras: [ { "name" => "house", "strength" => 0.5 } ])

      expect(goblin.art_recipe).to eq(
        "model" => "ponyDiffusionV6XL.safetensors",
        "family" => "sdxl",
        "loras" => [ { "name" => "house", "strength" => 0.5, "on" => true }, { "name" => "sprites", "strength" => 1.0, "on" => true } ],
        "positive" => "score_9, score_8_up, score_7_up, 16-bit pixel art, profile view, full body, Goblin, green skin, a rusty knife",
        "negative" => "score_4, score_5, score_6, photo, cropped",
        "width" => 896, "height" => 896, "transparent" => true,
        "parts" => { "prefix" => "score_9, score_8_up, score_7_up", "style" => "16-bit pixel art", "framing" => "profile view, full body",
                     "subject" => "Goblin, green skin, a rusty knife", "detail" => "" }
      )

      goblin.update!(art_model: "anima-preview.safetensors")
      expect(goblin.art_recipe).to include("model" => "anima-preview.safetensors", "family" => "anima")
      expect(goblin.art_recipe["positive"]).to start_with("masterpiece, best quality, 16-bit pixel art")
    end

    it "uses the description when the entry has no specifics, and the configured model by default" do
      recipe = goblin.art_recipe
      expect(recipe["positive"]).to end_with("Goblin, #{goblin.description}")
      expect(recipe["model"]).to eq(Comfy.config[:model])
    end
  end
end
