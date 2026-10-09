# frozen_string_literal: true

require "rails_helper"

RSpec.describe Item do
  let(:world) { create_world }

  it "treats equipment as flat stat bonuses" do
    item = world.items.new(name: "Mace", category: "sword", stats: { "atk" => "11", "def" => "", "agi" => "0" })
    expect(item.stats).to eq("atk" => 11)
    expect(item).to be_valid
    expect(item.slot).to eq("weapon")
    expect(item.to_equipment).to eq("stats" => { "atk" => 11 })
  end

  it "does not let equipment carry effects or consumables carry stats" do
    expect(world.items.new(name: "Odd", category: "sword", target: "self", effects: [ { primitive: "escape" } ]))
      .not_to be_valid
    expect(world.items.new(name: "Odd", category: "consumable", stats: { atk: 1 }, target: "self",
                           effects: [ { primitive: "escape" } ])).not_to be_valid
  end

  it "validates consumable effects with the engine" do
    potion = world.items.new(name: "Potion", category: "consumable", target: "single_ally",
                             effects: [ { primitive: "heal", power: "30" } ])
    expect(potion).to be_valid
    potion.target = ""
    expect(potion.target).to be_nil
    expect(potion).not_to be_valid
    expect(potion.errors[:effects].first).to match(/targeting/)
  end

  it "knows who equips and drops it" do
    sword = create_item(world)
    knight = create_job(world)
    create_job(world, slug: "mage", equip_categories: %w[rod])
    goblin = create_monster(world, drops: [ { item: "sword", chance: 10 } ])
    expect(sword.equippable_by).to eq([ knight ])
    expect(sword.dropped_by).to eq([ goblin ])
  end

  it "rejects unknown categories and stats" do
    item = world.items.new(name: "Thing", category: "lightsaber", stats: { "luck" => 3 })
    expect(item).not_to be_valid
    expect(item.errors.attribute_names).to include(:category, :stats)
  end
end
