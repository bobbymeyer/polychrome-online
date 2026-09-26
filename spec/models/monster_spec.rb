# frozen_string_literal: true

require "rails_helper"

RSpec.describe Monster do
  let(:world) { create_world }

  it "requires a complete stat block within caps" do
    monster = world.monsters.new(name: "Blob", stats: monster_stats.except("agi"))
    expect(monster).not_to be_valid
    expect(monster.errors[:stats]).to include(/missing agi/)

    monster.stats = monster_stats(max_hp: 0, str: "strong")
    expect(monster).not_to be_valid
    expect(monster.errors[:stats].first).to match(/max_hp, str/)
  end

  it "stores only non-neutral affinities and validates them" do
    monster = world.monsters.new(name: "Blob", stats: monster_stats,
                                 elements: { "fire" => "weak", "ice" => "normal", "bolt" => "" })
    expect(monster.elements).to eq("fire" => "weak")
    monster.elements = { "plasma" => "weak", "fire" => "hates" }
    expect(monster).not_to be_valid
    expect(monster.errors[:elements]).to include("plasma is not an element", "hates is not an affinity")
  end

  describe "AI script" do
    before { create_ability(world, slug: "cure", kind: "magic", target: "single_ally", effects: [ { primitive: "heal", power: 20 } ]) }

    it "turns form rows into engine rules" do
      rows = {
        "0" => { "self_hp_below" => "30", "ally_hp_below" => "", "ally_ko" => "0", "round_multiple" => "",
                 "chance" => "50", "use" => "cure", "target" => "self" },
        "1" => { "ally_ko" => "1", "use" => "attack", "target" => "" },
        "2" => { "ally_ko" => "0", "use" => "", "target" => "" }
      }
      monster = world.monsters.new(name: "Blob", stats: monster_stats, ai_script: rows)
      expect(monster.ai_script).to eq([
        { "if" => { "self_hp_below" => 30, "chance" => 50 }, "use" => "cure", "target" => "self" },
        { "if" => { "ally_ko" => true }, "use" => "attack" }
      ])
      expect(monster).to be_valid
    end

    it "only uses abilities from its own world's Grimoire" do
      monster = world.monsters.new(name: "Blob", stats: monster_stats, ai_script: [ { use: "meteor" } ])
      expect(monster).not_to be_valid
      expect(monster.errors[:ai_script]).to include(/meteor, which is not in the Grimoire/)
    end

    it "validates conditions and target strategies" do
      monster = world.monsters.new(name: "Blob", stats: monster_stats,
                                   ai_script: [ { if: { moon_phase: 3, chance: -1 }, use: "attack", target: "strongest" } ])
      expect(monster).not_to be_valid
      expect(monster.errors[:ai_script]).to include(/unknown condition moon_phase/, /chance must be a positive/, /unknown target strongest/)
    end
  end

  it "validates drops against the Armory" do
    create_item(world, slug: "potion", category: "consumable", stats: {}, target: "single_ally",
                       effects: [ { primitive: "heal", power: 30 } ])
    monster = world.monsters.new(name: "Blob", stats: monster_stats,
                                 drops: { "0" => { "item" => "potion", "chance" => "30" }, "1" => { "item" => "", "chance" => "" },
                                          "2" => { "item" => "elixir", "chance" => "150" } })
    expect(monster.drops).to eq([ { "item" => "potion", "chance" => 30 }, { "item" => "elixir", "chance" => 150 } ])
    expect(monster).not_to be_valid
    expect(monster.errors[:drops]).to contain_exactly("elixir is not in the Armory", "elixir chance must be 1–100")
  end

  it "validates the variant recipe" do
    monster = world.monsters.new(name: "Blob", stats: monster_stats, variant: { hue: "400", scale: "100", flip: "1" })
    expect(monster.variant).to eq("hue" => 400, "flip" => true)
    expect(monster).not_to be_valid
    expect(monster.errors[:variant]).to include(/hue/)
  end

  it "exports an enemy spec the engine accepts" do
    create_ability(world)
    monster = create_monster(world, elements: { fire: "weak" }, status_immune: %w[sleep], exp: 5, gil: 7,
                                    ai_script: [ { if: { chance: 40 }, use: "fire" }, { use: "attack" } ])
    spec = monster.to_engine(count: 2)
    expect(spec).to include("id" => "goblin", "count" => 2, "abilities" => [ "fire" ],
                            "rewards" => { "exp" => 5, "gil" => 7, "abp" => 0 })

    state = world.battle(seed: 1, party: [ { id: "hero", stats: monster_stats(max_hp: 200) } ], monsters: { "goblin" => 2 })
    expect(state["units"].map { |u| u["id"] }).to eq(%w[hero goblin_a goblin_b])
    expect(state["abilities"].keys).to contain_exactly("fire", "attack")
  end
end
