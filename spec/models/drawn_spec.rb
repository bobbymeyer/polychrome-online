# frozen_string_literal: true

require "rails_helper"

RSpec.describe Drawn do
  let(:world) { base_world }
  let(:goblin) { world.monsters.find_by!(slug: "goblin") }

  it "reads art as the subject's own, and makes an Art only when something is written" do
    expect([ goblin.art_notes, goblin.art_loras, goblin.image_seed ]).to eq([ nil, [], nil ])
    goblin.update!(name: "Goblin", art_notes: "")
    expect(goblin.reload.art).to be_nil

    goblin.update!(art_notes: "green, grinning", art_loras: { "0" => { name: "goblin.safetensors", strength: "0.5" }, "1" => { name: "" } },
                   image_seed: 42, image_recipe: { "model" => "pony" })
    goblin.reload
    expect([ goblin.art_notes, goblin.image_seed, goblin.image_recipe ]).to eq([ "green, grinning", 42, { "model" => "pony" } ])
    expect(goblin.art_loras).to eq([ { "name" => "goblin.safetensors", "strength" => 0.5, "on" => true } ])
    expect { goblin.destroy! }.to change(Art, :count).by(-1)
  end

  it "goes with a world's books when they're copied" do
    goblin.update!(art_notes: "green, grinning", image_seed: 7)
    copy = World.create!(name: "Copy", slug: "copy")
    copy.copy_books_from!(world)
    copied = copy.monsters.find_by!(slug: "goblin")
    expect([ copied.art_notes, copied.image_seed ]).to eq([ "green, grinning", 7 ])
    expect(copied.art).not_to eq(goblin.art)
  end
end
