# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe "Composing an image recipe (§8)" do
  describe ArtDirection do
    it "cleans LoRA rows from a form: blanks dropped, strength a float, 1.0 by default" do
      rows = { "0" => { "name" => " house.safetensors ", "strength" => "0.75" }, "1" => { "name" => "hero", "strength" => "" }, "2" => { "name" => "" } }
      expect(described_class.loras(rows)).to eq([ { "name" => "house.safetensors", "strength" => 0.75 }, { "name" => "hero", "strength" => 1.0 } ])
      expect(described_class.loras([ { name: "x", strength: 99 } ])).to eq([ { "name" => "x", "strength" => 5.0 } ])
    end

    it "lets later layers override a LoRA's strength, and 0 turn it off" do
      world = [ { "name" => "house", "strength" => 0.8 }, { "name" => "grain", "strength" => 0.3 } ]
      type = [ { "name" => "profile", "strength" => 1 } ]
      entry = [ { "name" => "house", "strength" => 0.4 }, { "name" => "grain", "strength" => 0 } ]
      expect(described_class.merge_loras(world, type, entry)).to eq(
        [ { "name" => "house", "strength" => 0.4 }, { "name" => "profile", "strength" => 1.0 } ]
      )
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

    it "composes world style, then type framing, then the entry, with every layer's LoRAs" do
      world.update!(art_style: "16-bit pixel art", art_negative: "photo", art_checkpoint: "pixel.safetensors",
                    art_loras: [ { "name" => "house", "strength" => 0.8 } ])
      world.art_type("monster").update!(prompt: "profile view, full body", negative: "cropped", width: 768, height: 768,
                                        loras: [ { "name" => "sprites", "strength" => 1 } ])
      goblin.update!(art_notes: "green skin, a rusty knife", art_loras: [ { "name" => "house", "strength" => 0.5 } ])

      expect(goblin.art_recipe).to eq(
        "checkpoint" => "pixel.safetensors",
        "loras" => [ { "name" => "house", "strength" => 0.5 }, { "name" => "sprites", "strength" => 1.0 } ],
        "positive" => "16-bit pixel art, profile view, full body, Goblin, green skin, a rusty knife",
        "negative" => "photo, cropped",
        "width" => 768, "height" => 768, "transparent" => true
      )
    end

    it "uses the description when the entry has no specifics, and the configured checkpoint by default" do
      recipe = goblin.art_recipe
      expect(recipe["positive"]).to end_with("Goblin, #{goblin.description}")
      expect(recipe["checkpoint"]).to eq(Comfy.config[:checkpoint])
    end
  end
end
