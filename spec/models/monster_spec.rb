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
                                 affinities: { "fire" => "weak", "ice" => "normal", "electric" => "" })
    expect(monster.affinities).to eq("fire" => "weak")
    monster.affinities = { "plasma" => "weak", "fire" => "hates" }
    expect(monster).not_to be_valid
    expect(monster.errors[:affinities]).to include("plasma is not one of this world's types", "hates is not an affinity")
    monster.base_type = "fairy"
    expect(monster).not_to be_valid
    expect(monster.errors[:base_type]).to be_present
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

  it "stays in the Bestiary while an ability summons it, a table rolls it, a template makes it a boss or someone fights as it" do
    sprite = create_monster(world, slug: "sprite")
    expect(sprite.destroy).to be_truthy # nothing names it yet

    rat = create_monster(world, slug: "rat")
    create_ability(world, slug: "call_rat", target: "self", effects: [ { primitive: "summon", creature: "rat", duration: 2 } ])
    world.encounter_tables.create!(name: "Sewers", slug: "sewers", terrain: "cave", tier: 1, entries: [ { weight: 1, monsters: { "rat" => 2 } } ])
    expect(rat.destroy).to be(false)
    expect(rat.errors.full_messages.to_sentence).to eq("Rat is still needed: Call rat summons it and Sewers rolls it. Change those first.")
    expect(world.monsters.where(slug: "rat")).to exist

    boss = create_monster(world, slug: "rat_king")
    world.location_templates.create!(name: "Nest", slug: "nest", kind: "dungeon", config: { "boss" => { "rat_king" => 1 } })
    expect(boss.destroy).to be(false)
    expect(boss.errors.full_messages.to_sentence).to include("it is the boss of Nest")
  end

  it "takes only battle abilities in its script: a field ability is a move outside battle" do
    appraise = base_world.abilities.field.first # the base world has field abilities, with its skills
    monster = base_world.monsters.new(name: "Blob", stats: monster_stats, ai_script: [ { use: appraise.slug } ])
    expect(monster).not_to be_valid
    expect(monster.errors[:ai_script]).to include("rule 1 uses #{appraise.slug}, a field ability, which can't be used in battle")
  end

  it "takes only battle abilities in its script (an unknown one is refused too)" do
    monster = world.monsters.new(name: "Blob", stats: monster_stats, ai_script: [ { use: "appraise" } ])
    expect(monster).not_to be_valid
    expect(monster.errors[:ai_script]).to include("rule 1 uses appraise, which is not in the Grimoire")
  end

  it "keeps a rule's chance a percentage" do
    monster = world.monsters.new(name: "Blob", stats: monster_stats, ai_script: [ { if: { chance: 150 }, use: "attack" } ])
    expect(monster).not_to be_valid
    expect(monster.errors[:ai_script]).to include("rule 1 chance must be 1 to 100")
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
    monster = create_monster(world, base_type: "ghost", affinities: { fire: "weak" }, status_immune: %w[sleep], exp: 5, gil: 7,
                                    ai_script: [ { if: { chance: 40 }, use: "fire" }, { use: "attack" } ])
    spec = monster.to_engine(count: 2)
    expect(spec).to include("id" => "goblin", "count" => 2, "abilities" => [ "fire" ],
                            "rewards" => { "exp" => 5, "gil" => 7, "abp" => 0 })

    state = world.battle(seed: 1, party: [ { id: "hero", stats: monster_stats(max_hp: 200) } ], monsters: { "goblin" => 2 })
    expect(state["units"].map { |u| u["id"] }).to eq(%w[hero goblin_a goblin_b])
    expect(state["abilities"].keys).to contain_exactly("fire", "attack")
  end
end
