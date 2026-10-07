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

    it "takes a rule's moment and the type of blow it answers, and checks them" do
      create_ability(world)
      monster = create_monster(world, ai_script: [ { when: "hit", by: "fire", use: "fire", say: "Back at you." }, { when: "falls", by: "fire", use: "fire" }, { use: "attack" } ])
      expect(monster.ai_script.first).to include("when" => "hit", "by" => "fire")
      expect(monster.ai_script.second).not_to have_key("by") # only a hit is by something
      bad = world.monsters.new(name: "Blob", stats: monster_stats, ai_script: [ { when: "sneezes", use: "attack" }, { when: "hit", by: "plasma", use: "attack" } ])
      expect(bad).not_to be_valid
      expect(bad.errors[:ai_script]).to include(/unknown moment sneezes/, /blows of plasma, which isn't one of this world's types/)
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

  describe "phases" do
    let!(:second) { create_monster(world, slug: "goblin_king", name: "Goblin King", boss: true) }

    it "takes form rows, checks them against the Bestiary and keeps them in order, and exports each form for the engine" do
      create_ability(world)
      monster = create_monster(world, ai_script: [ { use: "fire", once: "1", say: " Burn. " }, { use: "attack" } ],
                                      phases: [ { hp_below: "50", becomes: "goblin_king", say: "Now you see.", restore: "10" }, { becomes: "" } ])
      expect(monster.ai_script.first).to eq("use" => "fire", "once" => true, "say" => "Burn.")
      expect(monster.phases).to eq([ { "hp_below" => 50, "becomes" => "goblin_king", "say" => "Now you see.", "restore" => 10 } ])
      expect(monster.forms).to eq([ second ])
      expect(second.form_of).to eq([ monster ])

      spec = monster.to_engine
      expect(spec["phases"].first).to include("hp_below" => 50, "say" => "Now you see.", "restore" => 10)
      expect(spec["phases"].first["becomes"]).to include("name" => "Goblin King", "boss" => true, "image" => { "book" => "monsters", "slug" => "goblin_king" })
      state = world.battle(seed: 1, party: [ { id: "hero", stats: monster_stats(max_hp: 200) } ], monsters: { "goblin" => 1 })
      expect(state["units"].last["phases"].first["becomes"]["name"]).to eq("Goblin King")

      bad = world.monsters.new(name: "Blob", stats: monster_stats, phases: [ { hp_below: 50, becomes: "nobody" }, { hp_below: 60, becomes: "goblin_king", restore: 500 } ])
      expect(bad).not_to be_valid
      expect(bad.errors[:phases]).to include(/phase 1 becomes nobody, which is not in the Bestiary/, /phase 2 restore must be 0 to 100/, /in order/)
      expect(world.monsters.new(name: "Self", slug: "self", stats: monster_stats, phases: [ { hp_below: 50, becomes: "self" } ])).not_to be_valid
    end

    it "keeps a form in the Bestiary while something becomes it" do
      create_monster(world, phases: [ { hp_below: 50, becomes: "goblin_king" } ])
      expect(second.destroy).to be(false)
      expect(second.errors.full_messages.to_sentence).to include("it is a form of Goblin")
    end
  end

  it "plays its own music, one of its world's tracks by name, and carries where it plays from into the engine" do
    track = world.tracks.create!(name: "Doom march", source: "link", url: "https://youtu.be/dQw4w9WgXcQ")
    monster = create_monster(world, boss: true, music: "track:#{track.id}")
    expect(monster.music_path).to eq(track.play_url)
    expect(monster.to_engine["music"]).to eq(track.play_url)
    expect(world.monsters.new(name: "Quiet", stats: monster_stats, music: "")).to be_valid # blank: the world's boss track
    bad = world.monsters.new(name: "Loud", stats: monster_stats, music: "track:999")
    expect(bad).not_to be_valid
    expect(bad.errors[:music]).to include(/isn't one of Testland's tracks/)
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
