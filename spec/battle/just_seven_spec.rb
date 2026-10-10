# frozen_string_literal: true

# The mechanics The Just Seven's guardians brought to the engine (docs/ODA.md,
# The Just Seven): each dungeon's, built just before the party gets there.
RSpec.describe "The Just Seven's mechanics" do
  include BattleHelpers

  let(:hero) { { id: "hero", name: "Hero", stats: stats(max_hp: 300, max_mp: 60, str: 14, atk: 14, mag: 14, agi: 40), abilities: %w[fire] } }
  let(:ward) { { id: "ward", name: "Ward", stats: stats(max_hp: 200, max_mp: 20, agi: 30), hp: 150, abilities: [] } }
  let(:moves) { {} }
  let(:enemies) { [] }

  def battle(party: [ hero, ward ], **options)
    build_battle(party: party, enemies: enemies, abilities: BattleFixtures.abilities.merge(moves), **options)
  end

  def held(state, id) = unit(state, id)["statuses"].find { |s| s["kind"] == "held" }

  def holding(state, id, by: "crab", breaks: "hit", tear: 0, turns: 3)
    with_unit(state, id, statuses: [ { "kind" => "held", "turns" => turns, "by" => by, "breaks" => breaks, "tear" => tear } ])
  end

  describe "grabs (Clamp, Coil)" do
    let(:moves) do
      { clamp: { name: "Clamp", kind: "skill", target: "single_enemy", effects: [ { primitive: "grab", duration: 3, breaks: "fire" } ] },
        coil: { name: "Coil", kind: "skill", target: "single_enemy", effects: [ { primitive: "grab", duration: 3, tear: 10 } ] } }
    end
    let(:enemies) do
      [ { id: "crab", name: "Crab", stats: stats(max_hp: 3000, agi: 1, def: 10, mdef: 10), types: %w[normal], abilities: %w[clamp coil],
          ai: [ { use: "clamp", target: "lowest_hp" } ] } ]
    end

    it "holds its target fast: no command, and its turns pass it by" do
      state, = apply(battle, command("hero", "attack", "crab"))
      state, events = apply(state, command("ward", nil, kind: "defend"))
      expect(of_type(events, :status_applied)).to include(include("target" => "ward", "status" => "held", "by" => "crab"))
      expect(held(state, "ward")).to include("by" => "crab", "breaks" => "fire", "turns" => 3)
      expect(Battle::State.awaiting_input(state)).to eq([ "hero" ])

      _, events = apply(state, command("hero", "attack", "crab"))
      expect(of_type(events, :turn_skipped)).to include(include("unit" => "ward", "reason" => "held"))
    end

    it "breaks on the kind of blow it breaks on, and only that" do
      state = holding(battle, "ward", breaks: "fire")
      state, events = apply(state, command("hero", "attack", "crab"))
      expect(of_type(events, :status_expired).select { |e| e["status"] == "held" }).to be_empty # force only clenches it
      expect(held(state, "ward")).not_to be_nil

      _, events = apply(holding(battle, "ward", breaks: "fire"), command("hero", "fire", "crab"))
      expect(of_type(events, :status_expired)).to include(include("target" => "ward", "status" => "held", "reason" => "freed"))
    end

    it "tears the one it held as it comes free: the grip's damage, not the striker's" do
      state = holding(battle, "ward", tear: 10)
      _, events = apply(state, command("hero", "attack", "crab"))
      expect(of_type(events, :damage)).to include(include("target" => "ward", "amount" => 20, "status" => "held"))
      expect(of_type(events, :status_expired)).to include(include("target" => "ward", "reason" => "freed"))
    end

    it "lets go when the holder falls or leaves the field" do
      state = holding(battle, "ward")
      _, events = apply(state, gm("set_hp", unit: "crab", value: 0))
      expect(of_type(events, :status_expired)).to include(include("target" => "ward", "status" => "held", "reason" => "holder_fell"))

      _, events = apply(holding(battle, "ward"), gm("dismiss", unit: "crab"))
      expect(of_type(events, :status_expired)).to include(include("target" => "ward", "reason" => "holder_left"))
    end

    it "wears off, and a cure frees them (grease)" do
      state = holding(battle, "ward", breaks: "fire", turns: 1)
      _, events = apply(state, command("hero", "attack", "crab"))
      expect(of_type(events, :status_expired)).to include(include("target" => "ward", "status" => "held", "reason" => "wore_off"))

      state = with_unit(holding(battle, "ward", breaks: "fire"), "hero", abilities: %w[esuna fire])
      _, events = apply(state, command("hero", "esuna", "ward"))
      expect(of_type(events, :status_expired)).to include(include("target" => "ward", "status" => "held", "reason" => "cured"))
    end

    it "takes the grab from the book's words: what breaks it, how long, how much it tears" do
      bad = ->(effect) { Battle::State.validate_ability!({ "id" => "x", "target" => "single_enemy", "effects" => [ { "primitive" => "grab" }.merge(effect) ] }) }
      expect { bad.({ "breaks" => "fire", "duration" => 3, "tear" => 10 }) }.not_to raise_error
      expect { bad.({ "breaks" => "laughter" }) }.to raise_error(ArgumentError, /breaks on a hit or a type/)
      expect { bad.({ "duration" => 9 }) }.to raise_error(ArgumentError, /lasts 1 to/)
      expect { bad.({ "tear" => 150 }) }.to raise_error(ArgumentError, /tear/)
      expect { bad.({ "kind" => "held" }) }.to raise_error(ArgumentError, /does not take kind/)
    end
  end

  describe "a thief among the monsters (the Raccoon)" do
    let(:moves) { { pilfer: { name: "Pilfer", kind: "skill", target: "single_enemy", effects: [ { primitive: "steal", chance: 95 } ] } } }
    let(:enemies) do
      [ { id: "raccoon", name: "Raccoon", stats: stats(max_hp: 3000, agi: 99, def: 10), types: %w[normal], abilities: %w[pilfer], ai: [ { use: "pilfer" } ] } ]
    end
    let(:items) { { potion: { name: "Potion", target: "single_ally", effects: [ { primitive: "heal", power: 10 } ], count: 2 } } }

    # The first seed whose round has the Raccoon's steal come off.
    def robbed
      (1..30).each do |seed|
        state, = apply(battle(seed: seed, items: items), command("hero", "attack", "raccoon"))
        state, events = apply(state, command("ward", nil, kind: "defend"))
        return [ state, events ] if of_type(events, :steal).any?
      end
      raise "no steal in thirty seeds"
    end

    it "takes from the party's bag, not from a drop table it hasn't got" do
      state, events = robbed
      expect(of_type(events, :steal)).to include(include("actor" => "raccoon", "item" => "potion", "name" => "Potion", "left" => 1))
      expect(state["items"]["potion"]["count"]).to eq(1)
      expect(unit(state, "raccoon")["pilfered"]).to eq(%w[potion])
    end

    it "gives it all back when it falls, or when the party wins the field" do
      state, = robbed
      after, events = apply(state, gm("set_hp", unit: "raccoon", value: 0))
      expect(of_type(events, :recovered)).to include(include("unit" => "raccoon", "items" => %w[potion], "names" => %w[Potion]))
      expect(after["items"]["potion"]["count"]).to eq(2)

      after, = apply(state, gm("end_battle", result: "victory"))
      expect(after["items"]["potion"]["count"]).to eq(2)
    end

    it "keeps it if it gets away" do
      state, = robbed
      after, events = apply(state, gm("dismiss", unit: "raccoon"))
      expect(of_type(events, :recovered)).to be_empty
      expect(after["items"]["potion"]["count"]).to eq(1)
      expect(unit(after, "raccoon")["pilfered"]).to eq(%w[potion])
    end

    it "misses when the bag is empty" do
      state, = apply(battle(items: {}), command("hero", "attack", "raccoon"))
      _, events = apply(state, command("ward", nil, kind: "defend"))
      expect(of_type(events, :miss)).to include(include("actor" => "raccoon", "reason" => "nothing_to_steal"))
    end
  end
end
