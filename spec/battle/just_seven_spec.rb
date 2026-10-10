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

  describe "answering a blow before it lands (Riposte, Hot Skin)" do
    let(:moves) do
      { riposte: { name: "Riposte", kind: "skill", target: "single_enemy", effects: [ { primitive: "physical", power: 60 } ] },
        long_shot: { name: "Long Shot", kind: "skill", target: "single_enemy", reach: true, effects: [ { primitive: "physical", power: 100 } ] } }
    end
    let(:enemies) do
      [ { id: "mantis", name: "Mantis", stats: stats(max_hp: 3000, str: 30, atk: 30, agi: 1, def: 10, mdef: 10), types: %w[normal],
          abilities: %w[riposte], ai: [ { when: "struck", use: "riposte" } ] } ]
    end
    let(:hero) { { id: "hero", name: "Hero", stats: stats(max_hp: 300, max_mp: 60, str: 14, atk: 14, mag: 14, agi: 40), abilities: %w[fire long_shot] } }

    def round(state, hero_move)
      apply(apply(state, command("hero", hero_move, "mantis")).first, command("ward", nil, kind: "defend"))
    end

    it "answers a blow up close first, and the blow still comes if the striker can take it" do
      _, events = round(battle, "attack")
      riposte = events.index { |e| e["type"] == "reacts" && e["trigger"] == "struck" }
      blow = events.index { |e| e["type"] == "damage" && e["target"] == "mantis" }
      expect(riposte).to be < blow
      expect(events[riposte]).to include("actor" => "mantis", "ability" => "riposte")
      expect(of_type(events, :damage)).to include(include("actor" => "mantis", "target" => "hero"))
    end

    it "stops the blow when its answer puts the striker down" do
      state = with_unit(battle, "hero", hp: 5)
      _, events = round(state, "attack")
      expect(of_type(events, :ko)).to include(include("target" => "hero"))
      expect(of_type(events, :damage).select { |e| e["target"] == "mantis" }).to be_empty
    end

    it "has no answer for a spell or a shot from range" do
      %w[fire long_shot].each do |move|
        _, events = round(battle, move)
        expect(of_type(events, :reacts)).to be_empty, move
        expect(of_type(events, :damage)).to include(include("target" => "mantis"))
      end
    end
  end

  describe "a bird that keeps a grudge, dives, and circles (the Cormorant)" do
    let(:moves) do
      { bill: { name: "Hooked Bill", kind: "skill", target: "single_enemy", effects: [ { primitive: "physical", power: 50 } ] },
        dive: { name: "Dive", kind: "skill", target: "single_enemy", charge: 1, effects: [ { primitive: "physical", power: 50, stumble: 1 } ] },
        lunge: { name: "Lunge", kind: "skill", target: "single_enemy", effects: [ { primitive: "physical", power: 50, stumble: 1 } ] },
        long_shot: { name: "Long Shot", kind: "skill", target: "single_enemy", reach: true, effects: [ { primitive: "physical", power: 100 } ] } }
    end
    let(:script) { [ { use: "bill", target: "last_hit" } ] }
    let(:enemies) do
      [ { id: "bird", name: "Cormorant", stats: stats(max_hp: 3000, str: 10, atk: 10, agi: 1, def: 10, mdef: 10), types: %w[normal],
          abilities: %w[bill dive], ai: script } ]
    end
    let(:hero) { { id: "hero", name: "Hero", stats: stats(max_hp: 300, max_mp: 60, str: 14, atk: 14, mag: 14, agi: 40), abilities: %w[fire long_shot] } }
    let(:ward) { { id: "ward", name: "Ward", stats: stats(max_hp: 200, max_mp: 20, str: 10, atk: 10, agi: 30), abilities: [] } }

    def aimed_at(events, id) = of_type(events, :cast).select { |e| e["actor"] == "bird" && e["targets"] == [ id ] }

    it "goes for whoever hit it last" do
      (1..6).each do |seed|
        state, = apply(battle(seed: seed), command("hero", "attack", "bird"))
        _, events = apply(state, command("ward", nil, kind: "defend"))
        expect(aimed_at(events, "hero")).not_to be_empty, "seed #{seed}"
      end
    end

    context "with a dive that takes a turn to come down" do
      let(:script) { [ { use: "dive", target: "last_hit" } ] }

      it "finds whoever hit it last as it comes down, not who it named" do
        state, = apply(battle, command("hero", "attack", "bird"))
        state, = apply(state, command("ward", nil, kind: "defend"))
        expect(unit(state, "bird")["statuses"]).to include(include("kind" => "charging", "aim" => "last_hit"))

        state, = apply(state, command("hero", nil, kind: "defend"))
        _, events = apply(state, command("ward", "attack", "bird")) # Ward lands one first: the dive turns
        expect(of_type(events, :cast)).to include(include("actor" => "bird", "ability" => "dive", "targets" => [ "ward" ]))
      end
    end

    it "is grounded for a turn when a blow that stumbles misses" do
      quick = with_unit(battle, "hero", stats: stats(max_hp: 300, max_mp: 60, str: 14, atk: 14, mag: 14, agi: 250))
      missed = (1..40).lazy.map do |seed|
        state = quick.merge("seed" => seed, "rng" => Battle::Rng.seed_state(seed))
        state, = apply(with_unit(state, "bird", ai: [ { "use" => "lunge" } ], abilities: %w[lunge]), command("hero", nil, kind: "defend"))
        apply(state, command("ward", nil, kind: "defend"))
      end.find { |_, events| of_type(events, :stumbled).any? }
      expect(missed).not_to be_nil
      state, events = missed
      expect(of_type(events, :stumbled)).to include(include("actor" => "bird", "turns" => 1))
      expect(unit(state, "bird")["statuses"]).to include(include("kind" => "down"))
    end

    it "circling, it's out of reach of blows, but a shot with the reach or a spell still finds it" do
      state = with_unit(battle, "bird", statuses: [ { "kind" => "away", "turns" => 2, "left" => 2, "self" => true, "power" => 0, "aloft" => true } ])
      expect { apply(state, command("hero", "attack", "bird")) }.to raise_error(Battle::InvalidAction, /out of reach/)
      expect { apply(state, command("hero", "long_shot", "bird")) }.not_to raise_error
      expect { apply(state, command("hero", "fire", "bird")) }.not_to raise_error

      gone = with_unit(battle, "bird", statuses: [ { "kind" => "away", "turns" => 2, "left" => 2, "self" => true, "power" => 0 } ])
      expect { apply(gone, command("hero", "fire", "bird")) }.to raise_error(Battle::InvalidAction, /out of reach/) # hiding, not circling
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
