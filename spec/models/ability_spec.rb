# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ability do
  let(:world) { create_world }

  it "derives a slug from the name and keeps it fixed" do
    ability = world.abilities.create!(name: "Double Cut", kind: "skill", target: "single_enemy",
                                      effects: [ { primitive: "physical", power: 60, hits: 2 } ])
    expect(ability.slug).to eq("double_cut")
    expect(ability.to_param).to eq("double_cut")
    expect { ability.update(slug: "other") }.to raise_error(ActiveRecord::ReadonlyAttributeError)
  end

  it "requires unique slugs within a world only" do
    create_ability(world)
    expect(world.abilities.new(slug: "fire", name: "Fire 2", kind: "magic", target: "self",
                               effects: [ { primitive: "heal", power: 1 } ])).not_to be_valid
    expect { create_ability(create_world(slug: "elsewhere")) }.not_to raise_error
  end

  it "reserves the built-in attack slug" do
    ability = world.abilities.new(slug: "attack", name: "Attack", target: "single_enemy",
                                  effects: [ { primitive: "physical" } ])
    expect(ability).not_to be_valid
    expect(ability.errors[:slug]).to include(/reserved/)
  end

  describe "effects from form rows" do
    let(:rows) do
      {
        "0" => { "primitive" => "elemental", "type" => "fire", "power" => "20", "hits" => "",
                 "chance" => "50", "stat" => "", "kind" => "" },
        "1" => { "primitive" => "status", "kind" => "poison", "chance" => "100", "duration" => "4", "power" => "9" },
        "2" => { "primitive" => "", "power" => "5" }
      }
    end

    it "keeps only the params each primitive takes, cast to integers, dropping blank rows" do
      ability = world.abilities.new(name: "Bio", kind: "magic", target: "single_enemy", effects: rows)
      expect(ability.effects).to eq([
        { "primitive" => "elemental", "type" => "fire", "power" => 20 },
        { "primitive" => "status", "kind" => "poison", "chance" => 100, "duration" => 4 }
      ])
      expect(ability).to be_valid
    end

    it "reports the engine's reasons for rejecting an effect list" do
      ability = world.abilities.new(name: "Bad", kind: "magic", target: "single_enemy",
                                    effects: [ { primitive: "heal" } ])
      expect(ability).not_to be_valid
      expect(ability.errors[:effects]).to include("heal needs power")

      ability.effects = [ { primitive: "elemental", type: "fire", power: "lots" } ]
      expect(ability).not_to be_valid
      expect(ability.errors[:effects].first).to match(/power must be an integer/)

      ability.effects = []
      expect(ability).not_to be_valid
      expect(ability.errors[:effects]).to include("needs at least one effect")
    end
  end

  it "validates kind, targeting and gesture against the closed vocabularies" do
    ability = world.abilities.new(name: "X", kind: "prayer", target: "everyone", gesture: "moonwalk",
                                  effects: [ { primitive: "heal", power: 1 } ])
    expect(ability).not_to be_valid
    expect(ability.errors.attribute_names).to include(:kind, :target, :gesture)
  end

  it "exports the resolver's ability format" do
    ability = create_ability(world, gesture: "flash")
    expect(ability.to_engine).to eq(
      "name" => "Fire", "kind" => "magic", "target" => "single_enemy", "cost" => { "mp" => 4 },
      "effects" => [ { "primitive" => "elemental", "type" => "fire", "power" => 20 } ], "gesture" => "flash"
    )
  end

  it "knows which monsters use it" do
    ability = create_ability(world)
    user = create_monster(world, ai_script: [ { if: { chance: 50 }, use: "fire" }, { use: "attack" } ])
    create_monster(world, slug: "rat")
    expect(ability.monsters_using).to eq([ user ])
  end

  it "cannot be deleted while a monster's script uses it" do
    ability = create_ability(world)
    create_monster(world, slug: "imp", ai_script: [ { use: "fire" } ])
    expect(ability.destroy).to be(false)
    expect(ability.errors.full_messages.to_sentence).to eq("Fire is still used by Imp. Change their scripts first.")
    expect(world.abilities.where(slug: "fire")).to exist
  end

  it "wants a positive power on damage, healing, draining and shields" do
    ability = world.abilities.new(name: "Neg", kind: "magic", target: "single_enemy", effects: [ { primitive: "physical", power: -50 } ])
    expect(ability).not_to be_valid
    expect(ability.errors[:effects]).to include("power must be a positive number")
    ability.effects = [ { primitive: "heal", power: 0 } ]
    expect(ability).not_to be_valid
    expect(ability.errors[:effects]).to include("power must be a positive number")
  end

  it "cannot be deleted while a job teaches it" do
    ability = create_ability(world)
    job = create_job(world)
    job.job_levels.create!(level: 1, ability: ability)
    expect(ability.destroy).to be(false)
    expect(ability.errors.full_messages.to_sentence).to match(/job levels/i)
  end
end
