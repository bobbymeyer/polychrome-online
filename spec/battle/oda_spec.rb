# frozen_string_literal: true

# The mechanics Oda's archetypes brought to the engine (docs/ODA.md).
RSpec.describe "Oda's mechanics" do
  include BattleHelpers

  let(:hero) { { id: "hero", name: "Hero", stats: stats(max_hp: 200, max_mp: 60, str: 14, atk: 14, mag: 14, agi: 30), abilities: abilities } }
  let(:abilities) { [] }
  let(:dummy) { [ { id: "dummy", name: "Dummy", stats: stats(max_hp: 2000, agi: 1, def: 20, mdef: 20), types: %w[normal] } ] }
  let(:enemies) { dummy }

  def battle(party: [ hero ], **options)
    build_battle(party: party, enemies: enemies, **options)
  end

  def damage(events, target = "dummy")
    of_type(events, :damage).select { |e| e["target"] == target }.sum { |e| e["amount"] }
  end

  describe "stacks: gather and spend (Sheathe, chi)" do
    let(:abilities) { %w[sheathe draw palm] }

    it "gathers once a use, up to the most a status holds, and doesn't count them down" do
      state = battle
      6.times { state, = apply(state, command("hero", "sheathe")) }
      expect(unit(state, "hero")["statuses"]).to include(include("kind" => "sheathed", "stacks" => Battle::MAX_STACKS, "turns" => 1))
    end

    it "makes the move stronger for every stack, and spends them" do
      # The same rounds without the stacks: the dice fall the same way.
      plain = battle
      2.times { plain, = apply(plain, command("hero", kind: "defend")) }
      plain, plain_events = apply(plain, command("hero", "draw"))
      state = battle
      2.times { state, = apply(state, command("hero", "sheathe")) }
      state, events = apply(state, command("hero", "draw"))
      expect(of_type(events, :status_expired)).to include(include("status" => "sheathed", "reason" => "spent"))
      expect(unit(state, "hero")["statuses"].map { |s| s["kind"] }).not_to include("sheathed")
      expect(damage(events)).to be > damage(plain_events) * 3 / 2
      expect(unit(plain, "hero")["statuses"]).to be_empty
    end

    it "gathers chi from a blow, for the user, however many it hits" do
      state, events = apply(battle, command("hero", "palm", "dummy"))
      expect(of_type(events, :gathered)).to contain_exactly(include("unit" => "hero", "status" => "chi", "stacks" => 1))
      expect(unit(state, "dummy")["statuses"]).to be_empty
    end
  end

  describe "patience" do
    let(:abilities) { %w[draw] }
    let(:enemies) { BattleFixtures.goblins(3).map { |g| g.merge(stats: stats(max_hp: 900, agi: 99)) } }
    let(:hero) { { id: "hero", name: "Hero", stats: stats(max_hp: 900, str: 14, atk: 14, agi: 1), abilities: abilities } }

    it "is more power for every unit that went before the user this round" do
      _, events = apply(battle, command("hero", "draw"))
      expect(of_type(events, :patience)).to contain_exactly(include("actor" => "hero", "waited" => 3))
    end
  end

  describe "against the wounded, and pierce" do
    let(:abilities) { %w[zantetsu dragon_fist] }

    it "lands the bonus only on a target at the end of its HP" do
      _, healthy = apply(battle, command("hero", "zantetsu", "dummy"))
      _, low = apply(with_unit(battle, "dummy", hp: 500), command("hero", "zantetsu", "dummy"))
      expect(damage(low)).to be > damage(healthy) * 2
    end

    it "ignores part of the target's defence" do
      state = battle(abilities: BattleFixtures.abilities.merge(blunt: { name: "Blunt", kind: "skill", target: "single_enemy", effects: [ { primitive: "physical", power: 100 } ] }))
      state = with_unit(state, "hero", abilities: %w[attack blunt dragon_fist])
      _, pierced = apply(state, command("hero", "dragon_fist", "dummy"))
      _, blunt = apply(state, command("hero", "blunt", "dummy"))
      expect(damage(pierced)).to be > damage(blunt)
    end
  end

  describe "a mancer's magic" do
    let(:abilities) { %w[firaja fire] }
    let(:enemies) { [ { id: "dummy", name: "Dummy", stats: stats(max_hp: 2000, agi: 1), types: %w[water] } ] }

    it "pierces a resistance with an unresisted move" do
      _, events = apply(battle, command("hero", "firaja", "dummy"))
      expect(of_type(events, :damage).first["effectiveness"]).to eq(100)
      _, events = apply(battle, command("hero", "fire", "dummy"))
      expect(of_type(events, :damage).first["effectiveness"]).to eq(50)
    end

    it "leaves the caster reloading for its next turn after a big shot" do
      state, = apply(battle, command("hero", "firaja", "dummy"))
      expect(unit(state, "hero")["statuses"]).to include(include("kind" => "reloading"))
      expect(Battle::State.awaiting_input(state)).to be_empty
      state, events = apply(state, { type: "timeout" })
      expect(of_type(events, :turn_skipped)).to include(include("unit" => "hero", "reason" => "reloading"))
      expect(unit(state, "hero")["statuses"].map { |s| s["kind"] }).not_to include("reloading")
      expect(Battle::State.awaiting_input(state)).to eq([ "hero" ])
    end

    it "is stronger in its own type under the same-type rule" do
      mancer = hero.merge(types: %w[fire])
      _, plain = apply(battle(party: [ mancer ], enemies: [ { id: "dummy", name: "D", stats: stats(max_hp: 2000, agi: 1) } ]), command("hero", "fire", "dummy"))
      _, same = apply(battle(party: [ mancer ], enemies: [ { id: "dummy", name: "D", stats: stats(max_hp: 2000, agi: 1) } ], rules: { same_type: true }),
                      command("hero", "fire", "dummy"))
      expect(damage(same)).to eq(damage(plain) * Battle::SAME_TYPE_POWER / 100)
    end
  end

  describe "statuses" do
    let(:abilities) { %w[dispel regen reraise reflect fire scorch] }

    it "dispels the good ones and raised stats, and nothing else" do
      state = with_unit(battle, "dummy", statuses: [ { "kind" => "haste", "turns" => 3 }, { "kind" => "poison", "turns" => 3 } ],
                                         buffs: [ { "stat" => "str", "amount" => 50, "turns" => 3 }, { "stat" => "agi", "amount" => -20, "turns" => 3 } ])
      state, events = apply(state, command("hero", "dispel", "dummy"))
      expect(unit(state, "dummy")["statuses"].map { |s| s["kind"] }).to eq(%w[poison])
      expect(unit(state, "dummy")["buffs"].map { |b| b["stat"] }).to eq(%w[agi])
      expect(of_type(events, :status_expired)).to include(include("status" => "haste", "reason" => "dispelled"))
      _, events = apply(state, command("hero", "dispel", "dummy"))
      expect(of_type(events, :miss)).to include(include("reason" => "nothing_to_dispel"))
    end

    it "regenerates, given, and burns" do
      state = with_unit(battle, "hero", hp: 100)
      state, events = apply(state, command("hero", "regen", "hero"))
      state, events = apply(state, command("hero", "scorch", "dummy"))
      expect(of_type(events, :heal)).to include(include("target" => "hero", "regen" => true))
      state = with_unit(state, "dummy", statuses: [ { "kind" => "burn", "turns" => 3 } ])
      _, events = apply(state, command("hero", "dispel", "dummy"))
      expect(of_type(events, :damage)).to include(include("target" => "dummy", "status" => "burn", "amount" => 200))
    end

    it "gets a reraised unit back up once" do
      state, = apply(battle, command("hero", "reraise", "hero"))
      state = with_unit(state, "hero", hp: 1)
      state, events = apply(state, gm("set_hp", unit: "hero", value: 0))
      expect(events.map { |e| e["type"] }).not_to include("reraise") # a GM's word is final
      state = with_unit(battle, "hero", hp: 1, statuses: [ { "kind" => "reraise", "turns" => 5 } ])
      enemies = [ { id: "brute", name: "Brute", stats: stats(max_hp: 900, str: 200, atk: 200, agi: 99), ai: [ { use: "attack" } ] } ]
      state = build_battle(party: [ hero ], enemies: enemies)
      state = with_unit(state, "hero", hp: 1, statuses: [ { "kind" => "reraise", "turns" => 5 } ])
      state, events = apply(state, command("hero", "regen", "hero"))
      expect(types(events)).to include("ko", "reraise", "revive")
      expect(unit(state, "hero")["hp"]).to be_positive
      expect(unit(state, "hero")["statuses"].map { |s| s["kind"] }).not_to include("reraise")
    end

    it "turns single-target magic back on its caster" do
      state = with_unit(battle, "dummy", statuses: [ { "kind" => "reflect", "turns" => 3 } ])
      _, events = apply(state, command("hero", "fire", "dummy"))
      expect(of_type(events, :reflected)).to contain_exactly(include("unit" => "dummy", "back_to" => "hero"))
      expect(of_type(events, :damage).select { |e| e["actor"] == "hero" }.map { |e| e["target"] }).to eq([ "hero" ])
    end
  end

  describe "iai" do
    let(:enemies) { [ { id: "brute", name: "Brute", stats: stats(max_hp: 30, str: 10, atk: 10, agi: 99), ai: [ { use: "attack" } ] } ] }

    it "cuts the striker down before their blow lands" do
      state = with_unit(battle, "hero", statuses: [ { "kind" => "iai", "turns" => 2 } ], stats: stats(max_hp: 200, str: 60, atk: 60, agi: 1))
      state, events = apply(state, command("hero", "attack", "brute"))
      expect(of_type(events, :iai)).to contain_exactly(include("actor" => "hero", "target" => "brute"))
      expect(of_type(events, :damage).map { |e| e["target"] }).not_to include("hero")
      expect(state["status"]).to eq("victory")
    end
  end

  describe "a Ranger" do
    let(:abilities) { %w[long_shot call_hawk volley] }
    let(:enemies) { [ { id: "leaper", name: "Leaper", stats: stats(max_hp: 900, agi: 40), abilities: %w[jump], ai: [ { use: "jump" } ] } ] }

    it "reaches what's off the field" do
      hits = (1..10).map do |seed|
        state, events = apply(battle(seed: seed), command("hero", "long_shot", "leaper"))
        next 0 unless types(events).index("jump") < events.index { |e| e["type"] == "cast" && e["actor"] == "hero" } # it leapt before the shot

        expect(Battle::State.target_options(state, unit(state, "hero"), state["abilities"]["long_shot"])).to include("leaper")
        of_type(events, :damage).count { |e| e["target"] == "leaper" }
      end
      expect(hits.sum).to be_positive
    end

    it "keeps a companion for the whole battle" do
      state = build_battle(party: [ hero ], enemies: [ { id: "dummy", name: "Dummy", stats: stats(max_hp: 2000, agi: 1, str: 0, atk: 0) } ])
      state, = apply(state, command("hero", "call_hawk"))
      4.times { state, = apply(state, command("hero", "volley")) }
      expect(state["units"].find { |u| u["id"].start_with?("hawk") }).not_to include("gone" => true)
    end
  end

  describe "a Magician" do
    let(:party) { [ hero.merge(abilities: %w[quick mimic]), { id: "ally", name: "Ally", stats: stats(agi: 2, str: 20, atk: 20), abilities: %w[double_cut] } ] }

    it "gives an ally another go at once, once a round" do
      state, = apply(battle(party: party), command("hero", "quick", "ally"))
      _, events = apply(state, command("ally", "double_cut", "dummy"))
      expect(of_type(events, :quick)).to contain_exactly(include("actor" => "hero", "target" => "ally"))
      expect(of_type(events, :turn_start).select { |e| e["unit"] == "ally" }.size).to eq(2)
    end

    it "copies the last move an ally made, free" do
      state, = apply(battle(party: party), command("ally", "double_cut", "dummy"))
      state, = apply(state, command("hero", "mimic"))
      state, = apply(state, command("ally", "double_cut", "dummy"))
      _, events = apply(state, command("hero", "mimic"))
      expect(of_type(events, :mimic)).not_to be_empty
      expect(of_type(events, :cast).select { |e| e["actor"] == "hero" }).to include(include("ability" => "double_cut", "mimicked" => true))
    end
  end

  describe "a Thief's lift" do
    let(:abilities) { %w[pilfer_boon] }

    it "takes one of the target's good statuses for the thief" do
      state = with_unit(battle, "dummy", statuses: [ { "kind" => "haste", "turns" => 3 } ])
      state, events = nil, []
      10.times do |seed|
        state, events = apply(with_unit(battle(seed: seed), "dummy", statuses: [ { "kind" => "haste", "turns" => 3 } ]), command("hero", "pilfer_boon", "dummy"))
        break if of_type(events, :steal).any?
      end
      expect(of_type(events, :steal)).to contain_exactly(include("status" => "haste"))
      expect(unit(state, "hero")["statuses"].map { |s| s["kind"] }).to include("haste")
    end
  end

  describe "an Apothecary" do
    it "heals the badly hurt more with triage" do
      party = [ hero.merge(abilities: %w[triage]) ]
      _, slight = apply(with_unit(battle(party: party), "hero", hp: 190), command("hero", "triage", "hero"))
      _, deep = apply(with_unit(battle(party: party), "hero", hp: 20), command("hero", "triage", "hero"))
      expect(of_type(deep, :heal).first["amount"]).to be > of_type(slight, :heal).first["amount"]
    end

    it "makes items work half again as well with potency" do
      items = BattleFixtures.items(potion: 1)
      plain = with_unit(battle(items: items), "hero", hp: 10)
      potent = with_unit(battle(items: items), "hero", hp: 10, passives: %w[potency])
      _, a = apply(plain, { type: "command", actor: "hero", command: { kind: "item", item: "potion", target: "hero" } })
      _, b = apply(potent, { type: "command", actor: "hero", command: { kind: "item", item: "potion", target: "hero" } })
      expect(of_type(b, :heal).first["amount"]).to be > of_type(a, :heal).first["amount"]
    end
  end

  describe "masks" do
    let(:abilities) { %w[don_mask] }
    let(:enemies) { BattleFixtures.giant.map { |g| g.merge(ai: [ { use: "attack" } ], stats: stats(max_hp: 5000, agi: 1)) } }

    it "transforms the wearer: stronger, the mask's moves, the mask's type; then spent" do
      state, events = apply(battle, command("hero", "don_mask"))
      expect(of_type(events, :transformed)).to contain_exactly(include("mask" => "storm_mask", "abilities" => %w[raijin]))
      hero_unit = unit(state, "hero")
      expect(hero_unit["abilities"]).to include("raijin")
      expect(hero_unit["statuses"]).to include(include("kind" => "masked", "type" => "electric"))
      _, events = apply(state, command("hero", "attack", "oni"))
      expect(of_type(events, :damage).find { |e| e["target"] == "oni" }).to include("damage_type" => "electric")
      4.times { state, events = apply(state, command("hero", "attack", "oni")) unless Battle::State.awaiting_input(state).empty? }
      hero_unit = unit(state, "hero")
      expect(hero_unit["abilities"]).not_to include("raijin")
      expect(hero_unit["statuses"].map { |s| s["kind"] }).not_to include("masked")
    end

    it "hits a giant twice as hard" do
      plain, = apply(battle, command("hero", "attack", "oni"))
      _, plain_events = [ plain, apply(battle, command("hero", "attack", "oni")).last ]
      masked = with_unit(battle, "hero", statuses: [ { "kind" => "masked", "turns" => 3, "mask" => "storm_mask", "granted" => [] } ])
      _, events = apply(masked, command("hero", "attack", "oni"))
      expect(damage(events, "oni")).to be > damage(plain_events, "oni") * 2
    end

    it "won't have a coward" do
      state = with_unit(battle, "hero", coward: true)
      state, events = apply(state, command("hero", "don_mask"))
      expect(of_type(events, :miss)).to include(include("reason" => "coward"))
      expect(unit(state, "hero")["statuses"]).to be_empty
    end

    it "isn't put on again for someone whose turn runs out: a mask goes on once" do
      state, = apply(with_unit(battle, "hero", coward: true), command("hero", "don_mask"))
      _, events = apply(state, { type: "timeout" })
      expect(of_type(events, :miss).map { |e| e["reason"] }).not_to include("coward")
      expect(of_type(events, :attack).map { |e| e["actor"] }).to include("hero")
    end

    it "only puts on masks the battle has" do
      expect { build_battle(party: [ hero ], enemies: enemies, masks: {}) }.to raise_error(ArgumentError, /storm_mask/)
    end
  end

  describe "a coward" do
    it "finds no desperation move" do
      brute = { id: "brute", name: "Brute", stats: stats(max_hp: 900, agi: 1) }
      coward = hero.merge(desperation: "goblin_punch", coward: true)
      state = with_unit(build_battle(party: [ coward ], enemies: [ brute ]), "hero", hp: 1)
      brute[:stats] = stats(max_hp: 900, agi: 1, str: 0, atk: 0)
      state = with_unit(build_battle(party: [ coward ], enemies: [ brute ]), "hero", hp: 40)
      events = 20.times.flat_map { state, e = apply(state, command("hero", "attack", "brute")); e }
      expect(of_type(events, :desperation)).to be_empty
    end
  end
end
