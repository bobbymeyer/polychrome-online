# frozen_string_literal: true

RSpec.describe Battle::Resolver do
  let(:state) { build_battle(seed: 3) }

  describe "purity" do
    it "never mutates the state it is given" do
      frozen = Marshal.load(Marshal.dump(state))
      deep_freeze(frozen)
      expect { apply(frozen, command("bartz")) }.not_to raise_error
    end

    it "returns the same result for the same input" do
      mid, = full_round(state)
      expect(apply(mid, command("bartz", "double_cut"))).to eq(apply(mid, command("bartz", "double_cut")))
    end

    it "accepts symbol-keyed states and actions" do
      symbolized = symbolize(state)
      expect(apply(symbolized, command(:bartz))).to eq(apply(state, command("bartz")))
    end

    def deep_freeze(obj)
      case obj
      when Hash then obj.each_value { |v| deep_freeze(v) }
      when Array then obj.each { |v| deep_freeze(v) }
      end
      obj.freeze
    end

    def symbolize(obj)
      case obj
      when Hash then obj.to_h { |k, v| [ k.to_sym, symbolize(v) ] }
      when Array then obj.map { |v| symbolize(v) }
      else obj
      end
    end
  end

  describe "input phase" do
    it "accepts commands without resolving until the whole party is in" do
      s, events = apply(state, command("bartz"))
      expect(events).to eq([ { "type" => "command_accepted", "actor" => "bartz" } ])
      expect(s["inputs"]).to eq("bartz" => { "kind" => "ability", "ability" => "attack", "target" => nil })
      expect(s["rng"]).to eq(state["rng"])
    end

    it "lets a player change their command before the round runs" do
      s, = apply(state, command("bartz"))
      s, = apply(s, { type: "command", actor: "bartz", command: { kind: "defend" } })
      expect(s["inputs"]["bartz"]).to eq("kind" => "defend")
    end

    it "runs the round when the last input arrives" do
      s, events = full_round(state)
      expect(types(events)).to include("round_start", "turn_order", "turn_start", "round_end")
      expect(s["round"]).to eq(2)
      expect(s["inputs"]).to eq({})
    end

    it "does not wait for units who cannot act" do
      s = with_unit(state, "vivi", hp: 0)
      s = with_unit(s, "rosa", statuses: [ { "kind" => "sleep", "turns" => 2 } ])
      s, = apply(s, command("bartz"))
      s, events = apply(s, command("locke"))
      expect(types(events)).to include("round_start")
      expect(s["round"]).to eq(2)
    end

    describe "rejects" do
      def rejects(action, message, from: state)
        expect { apply(from, action) }.to raise_error(Battle::InvalidAction, message)
      end

      it("unknown action types") { rejects({ type: "cheat" }, /unknown action type/) }
      it("unknown units") { rejects(command("zidane"), /no unit/) }
      it("enemy actors") { rejects(command("goblin_a"), /not a party member/) }
      it("KO'd actors") { rejects(command("bartz"), /cannot act/, from: with_unit(state, "bartz", hp: 0)) }
      it("unknown abilities") { rejects(command("bartz", "ultima"), /no ability/) }
      it("abilities the unit does not know") { rejects(command("bartz", "fire"), /does not know/) }
      it("unknown command kinds") { rejects(command("bartz", kind: "summon"), /unknown command/) }
      it("targets that don't exist") { rejects(command("bartz", "attack", "nobody"), /no unit/) }
      it("attacking an ally") { rejects(command("bartz", "attack", "vivi"), /not an enemy/) }
      it("healing an enemy") { rejects(command("rosa", "cure", "goblin_a"), /not an ally/) }
      it("healing a fallen ally") { rejects(command("rosa", "cure", "bartz"), /down/, from: with_unit(state, "bartz", hp: 0)) }
      it("targeting a fallen enemy") { rejects(command("bartz", "attack", "goblin_a"), /down/, from: with_unit(state, "goblin_a", hp: 0)) }
      it("insufficient MP") { rejects(command("vivi", "meteor"), /lacks MP/, from: with_unit(state, "vivi", mp: 3)) }

      it "magic while silenced" do
        rejects(command("vivi", "fire"), /silenced/, from: with_unit(state, "vivi", statuses: [ { "kind" => "silence", "turns" => 2 } ]))
      end

      it "fleeing an inescapable battle" do
        rejects({ type: "command", actor: "bartz", command: { kind: "flee" } }, /cannot be fled/,
                from: build_battle(escapable: false))
      end

      it "anything once the battle is over" do
        over = Battle::State.normalize(state).merge("status" => "victory")
        rejects(command("bartz"), /battle is over/, from: over)
      end
    end

    it "allows raising a fallen ally" do
      s = with_unit(state, "bartz", hp: 0)
      expect { apply(s, command("rosa", "raise", "bartz")) }.not_to raise_error
    end
  end

  describe "round execution" do
    it "gives every living unit exactly one turn, in speed order" do
      _, events = full_round(state)
      order = of_type(events, :turn_order).sole["order"]
      expect(order).to match_array(state["units"].map { |u| u["id"] })
      started = of_type(events, :turn_start).map { |e| e["unit"] }
      expect(started).to eq(order & started)
      # anyone who did not get a turn was knocked out before it came
      expect(order - started).to all(satisfy { |id| of_type(events, :ko).any? { |e| e["target"] == id } })
    end

    it "puts much faster units first" do
      s = with_unit(state, "vivi", stats: stats(agi: 200, mag: 18, max_hp: 70, max_mp: 40))
      _, events = full_round(s)
      expect(of_type(events, :turn_order).sole["order"].first).to eq("vivi")
    end

    it "remembers each command as the unit's last command" do
      s, = apply(state, command("bartz", "double_cut"))
      s, = apply(s, command("vivi", "fire", "goblin_a"))
      s, = apply(s, command("rosa", "cure", "bartz"))
      s, = apply(s, command("locke", kind: "defend"))
      expect(unit(s, "bartz")["last_command"]).to include("ability" => "double_cut")
      expect(unit(s, "vivi")["last_command"]).to include("ability" => "fire", "target" => "goblin_a")
      expect(unit(s, "locke")["last_command"]).to eq("kind" => "defend")
    end

    it "spends MP and announces casts" do
      s, = apply(state, command("bartz"))
      s, = apply(s, command("vivi", "fire", "goblin_a"))
      s, = apply(s, command("rosa"))
      s, events = apply(s, command("locke"))
      expect(of_type(events, :cast).sole).to include("actor" => "vivi", "ability" => "fire", "mp_cost" => 4)
      expect(unit(s, "vivi")["mp"]).to eq(36)
    end

    it "retargets a single-target attack whose target already fell" do
      s = with_unit(state, "goblin_a", hp: 1)
      s = with_unit(s, "bartz", stats: stats(agi: 1, atk: 14, str: 14, max_hp: 120))
      s = with_unit(s, "locke", stats: stats(agi: 250, atk: 99, str: 99))
      s, = apply(s, command("bartz", "attack", "goblin_a"))
      s, = apply(s, command("vivi", kind: "defend"))
      s, = apply(s, command("rosa", kind: "defend"))
      _, events = apply(s, command("locke", "attack", "goblin_a"))

      bartz_attack = of_type(events, :attack).find { |e| e["actor"] == "bartz" }
      expect(bartz_attack["targets"]).not_to include("goblin_a") if bartz_attack
    end

    it "halves physical damage against defenders for the round only" do
      s = with_unit(state, "vivi", stats: stats(agi: 250, max_hp: 70, max_mp: 40, mag: 18))
      s, = apply(s, command("bartz", kind: "defend"))
      s, = apply(s, command("vivi", kind: "defend"))
      s, = apply(s, command("rosa", kind: "defend"))
      s, events = apply(s, command("locke", kind: "defend"))
      expect(of_type(events, :defend).size).to eq(4)
      expect(s["units"].map { |u| u["defending"] }).to all(be(false))
    end

    it "skips disabled units but still ticks their statuses" do
      s = with_unit(state, "goblin_a", statuses: [ { "kind" => "paralyze", "turns" => 1 } ])
      s, events = full_round(s, "defend")
      goblin_turn = events.drop_while { |e| e != { "type" => "turn_start", "unit" => "goblin_a" } }.first(4)
      expect(types(goblin_turn)).to eq(%w[turn_start turn_skipped status_expired turn_end])
      expect(goblin_turn[1]["reason"]).to eq("paralyze")
      expect(unit(s, "goblin_a")["statuses"]).to be_empty
    end

    it "fails a spell when silence landed between input and execution" do
      s = with_unit(state, "vivi", stats: stats(agi: 1, max_hp: 70, max_mp: 40, mag: 18))
      s, = apply(s, command("vivi", "fire", "goblin_a"))
      s = with_unit(s, "vivi", statuses: [ { "kind" => "silence", "turns" => 3 } ])
      s, = apply(s, command("bartz", kind: "defend"))
      s, = apply(s, command("rosa", kind: "defend"))
      _, events = apply(s, command("locke", kind: "defend"))
      expect(of_type(events, :action_failed).sole).to include("actor" => "vivi", "reason" => "silenced")
    end

    it "gives a unit revived mid-round no turn it did not command" do
      s = with_unit(state, "bartz", hp: 0)
      s = with_unit(s, "rosa", stats: stats(agi: 250, max_hp: 80, max_mp: 40, mag: 16))
      s, = apply(s, command("vivi", kind: "defend"))
      s, = apply(s, command("rosa", "raise", "bartz"))
      _, events = apply(s, command("locke", kind: "defend"))
      expect(of_type(events, :revive).sole["target"]).to eq("bartz")
      expect(of_type(events, :turn_start).map { |e| e["unit"] }).not_to include("bartz")
    end

    it "hits random enemies once per hit for random_enemy" do
      s = with_unit(state, "vivi", stats: stats(agi: 250, max_hp: 70, max_mp: 40, mag: 18))
      s, = apply(s, command("vivi", "meteor"))
      s, = apply(s, command("bartz", kind: "defend"))
      s, = apply(s, command("rosa", kind: "defend"))
      _, events = apply(s, command("locke", kind: "defend"))
      vivi_turn = turn_of(events, "vivi")
      expect(of_type(vivi_turn, :cast).sole["targets"]).to eq([])
      expect(of_type(vivi_turn, :damage).size).to be_between(1, 4)
    end

    it "strikes every enemy with an all_enemies spell" do
      s = with_unit(state, "vivi", stats: stats(agi: 250, max_hp: 70, max_mp: 40, mag: 18))
      s, = apply(s, command("vivi", "firaga_all"))
      s, = apply(s, command("bartz", kind: "defend"))
      s, = apply(s, command("rosa", kind: "defend"))
      _, events = apply(s, command("locke", kind: "defend"))
      expect(of_type(events, :cast).sole["targets"]).to eq(%w[goblin_a goblin_b goblin_c])
    end

    it "ends in victory with summed rewards" do
      s = build_battle(enemies: BattleFixtures.goblins(1))
      s = with_unit(s, "goblin", hp: 1)
      s, events = full_round(s)
      expect(s["status"]).to eq("victory")
      expect(of_type(events, :victory).sole["rewards"]).to eq("exp" => 6, "gil" => 12)
      expect(s["round"]).to eq(1)
    end

    it "rolls drops at victory with the battle's RNG, at most one per enemy" do
      enemies = BattleFixtures.goblins(2).map { |g| g.merge(drops: [ { item: "potion", chance: 100 }, { item: "elixir", chance: 100 } ]) }
      s = build_battle(enemies: enemies)
      s = with_unit(with_unit(s, "goblin_a", hp: 0), "goblin_b", hp: 1)
      s, events = full_round(s)
      expect(s["status"]).to eq("victory")
      expect(of_type(events, :victory).sole["drops"]).to eq(%w[potion potion])
    end

    it "drops nothing when the rolls fail" do
      s = build_battle(enemies: [ BattleFixtures.goblins(1).first.merge(drops: [ { item: "potion", chance: 0 } ]) ])
      s, events = apply(s, gm("end_battle", result: "victory"))
      expect(of_type(events, :victory).sole).to include("drops" => [], "rewards" => { "exp" => 6, "gil" => 12 })
    end

    it "ends in defeat when the party falls" do
      s = build_battle(party: [ BattleFixtures.party.first ], enemies: BattleFixtures.ogre)
      s = with_unit(s, "bartz", hp: 1, stats: stats(agi: 1, max_hp: 120))
      s, events = apply(s, command("bartz", kind: "defend"))
      expect(s["status"]).to eq("defeat")
      expect(types(events).last(2)).to eq(%w[defeat round_end])
    end

    it "lets the party flee" do
      s = with_unit(state, "locke", stats: stats(agi: 250))
      s, = apply(s, { type: "command", actor: "locke", command: { kind: "flee" } })
      s, = apply(s, command("bartz"))
      s, = apply(s, command("vivi"))
      s, events = apply(s, command("rosa"))
      flee = of_type(events, :flee).sole
      expect(s["status"]).to eq(flee["success"] ? "fled" : "input")
    end
  end

  describe "defaults" do
    def remember(state, id, cmd)
      state = Battle::State.normalize(state)
      unit(state, id)["last_command"] = Battle::State.normalize(cmd)
      state
    end

    it "timeout repeats each missing unit's last command, else attacks" do
      s = remember(state, "bartz", { kind: "ability", ability: "double_cut", target: nil })
      s = remember(s, "rosa", { kind: "ability", ability: "cure", target: "bartz" })
      s = with_unit(s, "rosa", mp: 0)
      s, = apply(s, command("vivi", kind: "defend"))
      _, events = apply(s, { type: "timeout" })

      expect(of_type(events, :timeout).sole["defaulted"]).to eq(%w[bartz rosa locke])
      expect(of_type(turn_of(events, "bartz"), :cast).sole["ability"]).to eq("double_cut")
      expect(of_type(turn_of(events, "rosa"), :attack)).not_to be_empty
      expect(of_type(turn_of(events, "locke"), :attack)).not_to be_empty
    end

    it "repeats defend" do
      s = remember(state, "bartz", { kind: "defend" })
      _, events = apply(s, { type: "timeout" })
      expect(of_type(turn_of(events, "bartz"), :defend)).not_to be_empty
    end

    it "does not repeat a spell the unit can no longer pay for" do
      s = remember(state, "vivi", { kind: "ability", ability: "meteor", target: nil })
      s = with_unit(s, "vivi", mp: 0)
      _, events = apply(s, gm("auto", unit: "vivi"))
      expect(of_type(events, :gm_override).sole["command"]).to include("ability" => "attack")
    end
  end

  describe "GM overrides" do
    it "auto fills one absent player's input, in the log" do
      s, = apply(state, command("bartz"))
      s, events = apply(s, gm("auto", unit: "vivi", note: "Vivi's player stepped away"))
      expect(events.sole).to include("type" => "gm_override", "op" => "auto", "unit" => "vivi",
                                     "note" => "Vivi's player stepped away")
      expect(s["inputs"]).to have_key("vivi")
    end

    it "auto can complete the round" do
      s, = apply(state, command("bartz"))
      s, = apply(s, command("vivi"))
      s, = apply(s, command("rosa"))
      _, events = apply(s, gm("auto", unit: "locke"))
      expect(types(events)).to include("round_start")
    end

    it "auto refuses units that already have input" do
      s, = apply(state, command("bartz"))
      expect { apply(s, gm("auto", unit: "bartz")) }.to raise_error(Battle::InvalidAction)
    end

    it "plays several absent players on auto in one override, with one event" do
      s = state
      _, events = apply(s, gm("auto", units: %w[vivi locke]))
      expect(events.first).to include("type" => "gm_override", "op" => "auto", "units" => %w[vivi locke])
      expect(events.count { |e| e["type"] == "gm_override" }).to eq(1)
      expect { apply(s, gm("auto", units: [])) }.to raise_error(Battle::InvalidAction)
    end

    it "execute_round runs immediately with defaults" do
      _, events = apply(state, gm("execute_round"))
      expect(events.first).to include("type" => "gm_override", "op" => "execute_round",
                                      "defaulted" => %w[bartz vivi rosa locke])
      expect(types(events)).to include("round_end")
    end

    it "set_hp knocks out, revives and ends the battle, all logged" do
      s, events = apply(state, gm("set_hp", unit: "goblin_a", value: 0))
      expect(types(events)).to eq(%w[gm_override ko])

      s, events = apply(s, gm("set_hp", unit: "goblin_a", value: 10))
      expect(types(events)).to eq(%w[gm_override revive])
      expect(unit(s, "goblin_a")["hp"]).to eq(10)

      s, events = apply(s, gm("set_hp", unit: "goblin_a", value: 9999))
      expect(events.sole["hp"]).to eq(45)

      s, = apply(s, gm("set_hp", unit: "goblin_a", value: 0))
      s, = apply(s, gm("set_hp", unit: "goblin_b", value: 0))
      s, events = apply(s, gm("set_hp", unit: "goblin_c", value: 0))
      expect(types(events)).to eq(%w[gm_override ko victory])
      expect(s["status"]).to eq("victory")
    end

    it "set_mp clamps" do
      s, = apply(state, gm("set_mp", unit: "vivi", value: -5))
      expect(unit(s, "vivi")["mp"]).to eq(0)
    end

    it "add_status applies a status and drops a now-disabled unit's input" do
      s, = apply(state, command("bartz"))
      s, events = apply(s, gm("add_status", unit: "bartz", status: "sleep", turns: 2))
      expect(types(events)).to eq(%w[gm_override status_applied])
      expect(s["inputs"]).not_to have_key("bartz")
    end

    it "remove_status cures" do
      s = with_unit(state, "bartz", statuses: [ { "kind" => "poison", "turns" => 5 } ])
      s, events = apply(s, gm("remove_status", unit: "bartz", status: "poison"))
      expect(events.last).to include("type" => "status_expired", "reason" => "gm")
      expect(unit(s, "bartz")["statuses"]).to be_empty
    end

    it "end_battle declares a result" do
      s, events = apply(state, gm("end_battle", result: "fled"))
      expect(types(events)).to eq(%w[gm_override flee])
      expect(s["status"]).to eq("fled")
    end

    it "rejects unknown ops and bad arguments" do
      expect { apply(state, gm("smite")) }.to raise_error(Battle::InvalidAction, /unknown GM op/)
      expect { apply(state, gm("add_status", unit: "bartz", status: "doom")) }.to raise_error(Battle::InvalidAction)
      expect { apply(state, gm("end_battle", result: "draw")) }.to raise_error(Battle::InvalidAction)
    end
  end

  describe "enemy AI" do
    let(:boss_fight) { build_battle(seed: 9, enemies: BattleFixtures.ogre) }

    def ogre_turn(events) = turn_of(events, "ogre")

    it "heals itself when low" do
      s = with_unit(boss_fight, "ogre", hp: 50)
      _, events = full_round(s, "defend")
      expect(of_type(ogre_turn(events), :cast).sole).to include("ability" => "cure", "targets" => [ "ogre" ])
    end

    it "follows round-based rules" do
      s = Battle::State.normalize(boss_fight).merge("round" => 3)
      _, events = full_round(s, "defend")
      expect(of_type(ogre_turn(events), :cast).sole["ability"]).to eq("war_cry")
    end

    it "targets the weakest party member when told to" do
      s = with_unit(boss_fight, "vivi", hp: 5)
      _, events = full_round(s, "defend")
      expect(of_type(ogre_turn(events), :attack).sole["targets"]).to eq([ "vivi" ])
    end

    it "skips rules it cannot pay for" do
      s = with_unit(boss_fight, "ogre", hp: 50, mp: 0)
      _, events = full_round(s, "defend")
      expect(of_type(ogre_turn(events), :attack)).not_to be_empty
    end

    it "falls back to attacking when silenced" do
      s = with_unit(boss_fight, "ogre", hp: 50, statuses: [ { "kind" => "silence", "turns" => 3 } ])
      _, events = full_round(s, "defend")
      expect(types(ogre_turn(events))).not_to include("action_failed")
      expect(of_type(ogre_turn(events), :attack)).not_to be_empty
    end
  end

  describe "desperation moves" do
    let(:party) { [ BattleFixtures.party.first.merge(desperation: "goblin_punch", stats: stats(max_hp: 400, str: 14, atk: 14, agi: 30, def: 200)) ] }
    let(:enemies) { [ { id: "slime", name: "Slime", stats: stats(max_hp: 5000, def: 200, str: 1, atk: 0), ai: [ { use: "attack" } ] } ] }

    def rounds(state, count)
      count.times.reduce([ state, [] ]) do |(s, log), _|
        s, events = apply(s, command("bartz"))
        [ s, log + events ]
      end
    end

    it "can turn an attack into the job's move at a quarter HP or less, once, for free" do
      state = with_unit(build_battle(seed: 3, party: party, enemies: enemies), "bartz", hp: 60)
      state, events = rounds(state, 30)
      moves = of_type(events, :desperation)
      expect(moves.size).to eq(1)
      expect(moves.first).to include("actor" => "bartz", "ability" => "goblin_punch", "name" => "Goblin Punch")
      after = events.drop_while { |e| e["type"] != "desperation" }
      expect(after[1]).to include("type" => "attack").or include("type" => "cast")
      expect(after[1]).to include("ability" => "goblin_punch", "mp_cost" => 0)
      expect(unit(state, "bartz")["desperation_used"]).to be(true)
    end

    it "never happens above a quarter HP, or to someone without one" do
      _, events = rounds(build_battle(seed: 3, party: party, enemies: enemies), 30)
      expect(of_type(events, :desperation)).to be_empty

      plain = [ party.first.except(:desperation) ]
      _, events = rounds(with_unit(build_battle(seed: 3, party: plain, enemies: enemies), "bartz", hp: 60), 30)
      expect(of_type(events, :desperation)).to be_empty
    end

    it "must be an ability the battle knows" do
      expect { build_battle(party: [ party.first.merge(desperation: "ultima") ], enemies: enemies) }
        .to raise_error(ArgumentError, /unknown desperation move: ultima/)
    end
  end

  describe "GM: units joining and leaving" do
    let(:goblin) { Battle::State.normalize(BattleFixtures.goblins(1).first.except(:count)) }

    it "brings in reinforcements with the next free letter, and a guest who fights on their own" do
      state = build_battle(enemies: BattleFixtures.goblins(2))
      state, events = apply(state, gm("add_unit", side: "enemy", unit: goblin, note: "More of them!"))
      expect(of_type(events, :unit_joined).first).to include("unit" => "goblin_c", "name" => "Goblin C", "side" => "enemy")

      cid = { "id" => "cid", "name" => "Cid", "stats" => stats(max_hp: 200, str: 20, atk: 20), "ai" => [ { "use" => "attack" } ] }
      state, = apply(state, gm("add_unit", side: "party", unit: cid))
      expect(unit(state, "cid")).to include("guest" => true, "side" => "party")
      expect(Battle::State.awaiting_input(state)).not_to include("cid")

      _, events = full_round(state)
      expect(of_type(events, :turn_order).first["order"]).to include("cid", "goblin_c")
      expect(of_type(events, :attack).map { |e| e["actor"] }).to include("cid")
    end

    it "lets an enemy leave, paying nothing for it, and wins if it was the last" do
      state = build_battle(enemies: BattleFixtures.goblins(2))
      state, = apply(state, gm("set_hp", unit: "goblin_a", value: 0))
      state, events = apply(state, gm("dismiss", unit: "goblin_b", note: "It runs!"))
      expect(types(events)).to include("unit_left", "victory")
      expect(of_type(events, :victory).first["rewards"]).to eq(unit(state, "goblin_a")["rewards"])
      expect(state["status"]).to eq("victory")
    end

    it "never dismisses a party member, and needs a unit the engine can build" do
      state = build_battle
      expect { apply(state, gm("dismiss", unit: "bartz")) }.to raise_error(Battle::InvalidAction, /party member/)
      expect { apply(state, gm("add_unit", side: "enemy", unit: { "id" => "blob" })) }.to raise_error(Battle::InvalidAction, /stats/)
      expect { apply(state, gm("add_unit", side: "enemy", unit: goblin.merge("abilities" => [ "ultima" ]))) }
        .to raise_error(Battle::InvalidAction, /unknown abilities: ultima/)
    end
  end
end
