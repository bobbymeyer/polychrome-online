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

  describe "the timing meter" do
    it "lands a Perfect a quarter harder, and never carries it into a repeated command" do
      normal, = apply(build_battle(seed: 5), command("bartz", "attack", "goblin_a"))
      perfect, = apply(build_battle(seed: 5), command("bartz", "attack", "goblin_a").merge(command: { kind: "ability", ability: "attack", target: "goblin_a", timing: "perfect" }))
      expect(perfect["inputs"]["bartz"]).to include("timing" => "perfect")
      expect(normal["inputs"]["bartz"]).not_to have_key("timing")

      state = build_battle(seed: 5, party: [ BattleFixtures.party.first ], enemies: [ { id: "slime", name: "Slime", stats: stats(max_hp: 5000) } ])
      _, plain = apply(state, command("bartz", "attack", "slime"))
      after, hard = apply(state, { type: "command", actor: "bartz", command: { kind: "ability", ability: "attack", target: "slime", timing: "perfect" } })
      expect(of_type(hard, :attack).first).to include("perfect" => true)
      expect(of_type(hard, :damage).first["amount"]).to be > of_type(plain, :damage).first["amount"]

      _, events = apply(after, { type: "timeout" })
      expect(of_type(events, :attack).first).not_to have_key("perfect")
    end
  end

  describe "trying something" do
    let(:party) { [ BattleFixtures.party.first.merge(level: 5) ] }
    let(:state) { build_battle(seed: 9, party: party, enemies: BattleFixtures.goblins(2)) }
    let(:idea) { { type: "command", actor: "bartz", command: { kind: "custom", text: "Kick the brazier onto them", target: "goblin_a" } } }

    it "waits for the GM's ruling, then rolls for it on the unit's turn" do
      waiting, events = apply(state, idea)
      expect(waiting["inputs"]["bartz"]).to include("kind" => "custom", "text" => "Kick the brazier onto them")
      expect(types(events)).not_to include("round_start")

      ruling = gm("rule", unit: "bartz", stat: "agi", difficulty: "easy", aim: "all_enemies",
                          effects: [ { primitive: "elemental", type: "fire", power: 30 } ], success: "Burning coals everywhere!", failure: "It won't budge.")
      _, events = apply(waiting, ruling)
      roll = of_type(events, :custom_roll).sole
      expect(roll).to include("actor" => "bartz", "stat" => "agi", "difficulty" => "easy")
      expect(roll["roll"] <= roll["needed"]).to eq(roll["success"])
      expect(roll["line"]).to eq(roll["success"] ? "Burning coals everywhere!" : "It won't budge.")
      fire = of_type(events, :damage).select { |e| e["damage_type"] == "fire" }
      expect(fire.map { |e| e["target"] }.sort).to eq(roll["success"] ? %w[goblin_a goblin_b] : [])
    end

    it "is an Attack when time runs out before a ruling, and never repeats" do
      waiting, = apply(state, idea)
      after, events = apply(waiting, { type: "timeout" })
      expect(types(events)).to include("custom_action", "custom_unruled", "attack")
      _, events = apply(after, { type: "timeout" })
      expect(types(events)).not_to include("custom_action")
    end

    it "only takes a ruling on a pending idea, from the closed vocabulary" do
      expect { apply(state, gm("rule", unit: "bartz", stat: "agi", difficulty: "easy")) }.to raise_error(Battle::InvalidAction, /isn't trying/)
      waiting, = apply(state, idea)
      expect { apply(waiting, gm("rule", unit: "bartz", stat: "luck", difficulty: "easy")) }.to raise_error(Battle::InvalidAction, /stat/)
      expect { apply(waiting, gm("rule", unit: "bartz", stat: "agi", difficulty: "easy", effects: [ { primitive: "nuke" } ])) }
        .to raise_error(Battle::InvalidAction, /unknown primitive/)
      expect { apply(waiting, gm("rule", unit: "bartz", stat: "agi", difficulty: "easy", skill: "Stealth", bonus: 99)) }
        .to raise_error(Battle::InvalidAction, /bonus/)
    end

    it "adds a skill's bonus to the odds, and names the skill" do
      waiting, = apply(state, idea)
      plain = of_type(apply(waiting, gm("rule", unit: "bartz", stat: "agi", difficulty: "hard")).last, :custom_roll).sole
      skilled = of_type(apply(waiting, gm("rule", unit: "bartz", stat: "agi", difficulty: "hard", skill: "Stealth", bonus: 15)).last, :custom_roll).sole
      expect(skilled["needed"]).to eq([ plain["needed"] + 15, 95 ].min)
      expect(skilled).to include("skill" => "Stealth")
      expect(plain).not_to have_key("skill")
    end
  end

  describe "job mechanics" do
    let(:tough) { stats(max_hp: 900, str: 30, atk: 30, agi: 10, def: 100) }
    let(:knight) { { id: "knight", name: "Knight", stats: tough, abilities: %w[cover jump] } }
    let(:mage) { { id: "mage", name: "Mage", stats: stats(max_hp: 900, agi: 5, def: 100) } }
    let(:brute) { [ { id: "brute", name: "Brute", stats: stats(max_hp: 3000, str: 20, atk: 20, agi: 1), ai: [ { use: "attack" } ] } ] }

    def round(state, commands)
      commands.reduce([ state, [] ]) do |(s, log), (actor, cmd)|
        s, events = apply(s, { type: "command", actor: actor, command: cmd })
        [ s, log + events ]
      end
    end

    it "lets a Knight's Cover take the enemy's blows meant for an ally" do
      state = build_battle(seed: 2, party: [ knight, mage ], enemies: brute)
      _, events = round(state, "knight" => { kind: "ability", ability: "cover" }, "mage" => { kind: "defend" })
      hits = of_type(events, :damage).select { |e| e["actor"] == "brute" }
      expect(hits.map { |e| e["target"] }).to all(eq("knight"))
      expect(of_type(events, :covered).map { |e| e["for"] }.uniq).to include("mage") if of_type(events, :covered).any?
    end

    it "takes a Dragoon out of reach for a round, then lands the blow" do
      state = build_battle(seed: 2, party: [ knight.merge(agi: 50, stats: tough.merge("agi" => 50)) ], enemies: brute)
      state, events = round(state, "knight" => { kind: "ability", ability: "jump", target: "brute" })
      expect(types(events)).to include("jump")
      expect(of_type(events, :damage).map { |e| e["target"] }).not_to include("knight")
      expect(Battle::State.awaiting_input(state)).to be_empty

      _, events = apply(state, { type: "timeout" })
      land = of_type(events, :land).sole
      expect(land).to include("actor" => "knight", "target" => "brute")
      expect(of_type(events, :damage).first).to include("actor" => "knight", "target" => "brute")
    end

    describe "away" do
      it "hides the user for a round, then lets them act" do
        state = build_battle(seed: 2, party: [ knight.merge(abilities: %w[hide]) ], enemies: brute)
        state, events = round(state, "knight" => { kind: "ability", ability: "hide" })
        expect(of_type(events, :away).sole).to include("unit" => "knight", "turns" => 1)
        expect(of_type(events, :damage).map { |e| e["target"] }).not_to include("knight")
        expect(Battle::State.awaiting_input(state)).to be_empty

        state, events = apply(state, { type: "timeout" })
        expect(types(turn_of(events, "knight"))).to include("back")
        expect(Battle::State.awaiting_input(state)).to eq([ "knight" ])
      end

      it "sends an enemy off the field, where it loses its turns, then brings it back" do
        sure = BattleFixtures.abilities.merge(banish: BattleFixtures.abilities[:banish].merge(effects: [ { primitive: "away", who: "target", duration: 2 } ]))
        state = build_battle(seed: 2, party: [ knight.merge(abilities: %w[banish], stats: tough.merge("agi" => 50)) ], enemies: brute, abilities: sure)
        state, events = round(state, "knight" => { kind: "ability", ability: "banish", target: "brute" })

        expect(of_type(events, :away).sole).to include("unit" => "brute", "turns" => 2)
        expect(of_type(events, :turn_skipped).map { |e| [ e["unit"], e["reason"] ] }).to include([ "brute", "away" ])
        _, events = round(state, "knight" => { kind: "ability", ability: "attack", target: "brute" })
        expect(of_type(events, :miss)).to include(a_hash_including("actor" => "knight", "reason" => "no_target"))
        expect(of_type(events, :back).sole).to include("unit" => "brute")
        expect(of_type(events, :damage).select { |e| e["actor"] == "brute" }).to be_empty # coming back was its turn
      end

      it "keeps a High Jump in the air for two turns, then lands the blow" do
        state = build_battle(seed: 2, party: [ knight.merge(abilities: %w[high_jump], stats: tough.merge("agi" => 50)) ], enemies: brute)
        state, events = round(state, "knight" => { kind: "ability", ability: "high_jump", target: "brute" })
        expect(of_type(events, :jump).sole).to include("turns" => 2)
        state, events = apply(state, { type: "timeout" })
        expect(of_type(events, :land)).to be_empty
        _, events = apply(state, { type: "timeout" })
        expect(of_type(events, :land).sole).to include("actor" => "knight", "target" => "brute")
      end

      it "respects a unit that can't be sent away" do
        state = build_battle(seed: 2, party: [ knight.merge(abilities: %w[banish]) ], enemies: [ brute.first.merge(status_immune: %w[away]) ])
        _, events = round(state, "knight" => { kind: "ability", ability: "banish", target: "brute" })
        expect(of_type(events, :miss)).to include(a_hash_including("reason" => "immune", "status" => "away"))
      end
    end

    it "gives passives their moments: first strike, regen, clear mind, counter, second wind" do
      fast = knight.merge(passives: %w[first_strike regen mp_regen counter second_wind], hp: 100, mp: 0,
                          stats: tough.merge("agi" => 1, "max_mp" => 40))
      state = build_battle(seed: 4, party: [ fast ], enemies: brute)
      state, events = round(state, "knight" => { kind: "defend" })
      expect(of_type(events, :turn_order).first["order"].first).to eq("knight")
      expect(of_type(events, :heal)).to include(a_hash_including("target" => "knight", "regen" => true))
      expect(of_type(events, :mp_restored)).to include(a_hash_including("target" => "knight"))

      knocked = with_unit(state, "knight", hp: 1, passives: %w[second_wind])
      _, events = round(knocked, "knight" => { kind: "defend" })
      wind = of_type(events, :second_wind).sole
      expect(wind).to include("target" => "knight", "hp" => 225)

      counters = (1..30).flat_map { |seed| round(build_battle(seed: seed, party: [ fast ], enemies: brute), "knight" => { kind: "defend" }).last }
      expect(of_type(counters, :counter)).not_to be_empty
    end

    it "gives terrain moves the type of where the fight is" do
      state = build_battle(seed: 1, party: [ knight.merge(abilities: %w[gaia]) ], enemies: brute, terrain: "grass")
      _, events = round(state, "knight" => { kind: "ability", ability: "gaia" })
      expect(of_type(events, :damage).first).to include("damage_type" => "grass")
      expect(build_battle["terrain"]).to eq("normal")
    end

    describe "what jobs bring" do
      let(:ghost) { [ { id: "wisp", name: "Wisp", stats: stats(max_hp: 3000, agi: 1), types: %w[ghost], ai: [ { use: "attack" } ] } ] }
      let(:healer) { mage.merge(abilities: %w[cure], hp: 100, stats: mage[:stats].merge("mag" => 10)) }

      def cure_amount(unit, seed: 3)
        state = build_battle(seed: seed, party: [ unit ], enemies: brute)
        _, events = round(state, "mage" => { kind: "ability", ability: "cure", target: "mage" })
        of_type(events, :heal).find { |e| e["actor"] == "mage" }.fetch("amount")
      end

      it "gives Attack and the job's own command the job's type" do
        fighter = knight.merge(attack_type: "fighting", signature: "jump")
        _, events = round(build_battle(seed: 1, party: [ fighter ], enemies: brute), "knight" => { kind: "ability", ability: "attack" })
        expect(of_type(events, :damage).find { |e| e["actor"] == "knight" }).to include("damage_type" => "fighting")

        state, = round(build_battle(seed: 1, party: [ fighter ], enemies: brute), "knight" => { kind: "ability", ability: "jump", target: "brute" })
        _, events = apply(state, { type: "timeout" })
        expect(of_type(events, :damage).find { |e| e["actor"] == "knight" }).to include("damage_type" => "fighting")

        _, events = round(build_battle(seed: 1, party: [ knight ], enemies: brute), "knight" => { kind: "ability", ability: "attack" })
        expect(of_type(events, :damage).find { |e| e["actor"] == "knight" }).not_to have_key("damage_type")
      end

      it "scales a move by its mastery, and a mastered one brings its job's stats" do
        plain = cure_amount(healer)
        expect(cure_amount(healer.merge(mastery: { "cure" => { "power" => 150 } }))).to be_within(1).of(plain * 150 / 100)
        expect(cure_amount(healer.merge(mastery: { "cure" => { "power" => 100, "stats" => { "mag" => 26 } } }))).to be_within(1).of(plain * 42 / 26)
        expect(cure_amount(healer.merge(mastery: { "cure" => { "power" => 100, "stats" => { "mag" => 26 } } }))).to be > plain
      end

      it "never lets a character's type make them untouchable" do
        spirit = knight.merge(types: %w[normal], immune_as_resist: true)
        state = build_battle(seed: 2, party: [ spirit ], enemies: ghost)
        state = with_unit(state, "wisp", attack_type: "ghost") # a monster with a typed attack, for the test
        _, events = round(state, "knight" => { kind: "defend" })
        blow = of_type(events, :damage).find { |e| e["actor"] == "wisp" }
        expect(blow).to include("damage_type" => "ghost", "effectiveness" => 50)
        expect(Battle::Types.effectiveness("ghost", unit(state, "knight").except("immune_as_resist"))).to eq(0)
      end

      it "rejects mastery it can't use" do
        expect { build_battle(party: [ healer.merge(mastery: { "cure" => { "power" => 0 } }) ]) }.to raise_error(ArgumentError, /mastery power/)
        expect { build_battle(party: [ healer.merge(mastery: { "cure" => { "power" => 150, "stats" => { "luck" => 3 } } }) ]) }
          .to raise_error(ArgumentError, /mastery stats/)
        expect { build_battle(party: [ healer.merge(attack_type: "fairy") ]) }.to raise_error(ArgumentError, /attack type/)
      end
    end
  end

  describe "a world's own types" do
    let(:types) { { "chart" => { "plain" => {}, "hot" => { "cold" => 200, "hot" => 50 }, "cold" => {} }, "shrugs_off" => { "hot" => %w[sleep] } } }
    let(:scorch) { { scorch: { name: "Scorch", kind: "magic", target: "single_enemy", cost: { mp: 0 }, effects: [ { primitive: "elemental", type: "hot", power: 20 } ] } } }
    let(:mage) { [ { id: "mage", name: "Mage", stats: stats(mag: 20, agi: 50), abilities: %w[scorch] } ] }
    let(:blob) { [ { id: "blob", name: "Blob", stats: stats(max_hp: 900, agi: 1), types: %w[plain] } ] }

    def world_battle(**options)
      build_battle(party: mage, enemies: blob, abilities: scorch, types: types, **options)
    end

    def damage_to(enemy_types)
      enemies = [ { id: "blob", name: "Blob", stats: stats(max_hp: 900, agi: 1), types: enemy_types } ]
      state = build_battle(seed: 1, party: mage, enemies: enemies, abilities: scorch, types: types)
      _, events = apply(state, command("mage", "scorch", "blob"))
      of_type(events, :damage).find { |e| e["actor"] == "mage" }
    end

    it "carries the world's chart in the state and hits by it" do
      expect(world_battle).to include("types" => types, "terrain" => "plain")
      expect(damage_to(%w[cold])).to include("damage_type" => "hot", "effectiveness" => 200)
      expect(damage_to(%w[hot])).to include("effectiveness" => 50)
      expect(damage_to(%w[plain])).to include("effectiveness" => 100)
    end

    it "only takes types the world has" do
      expect { world_battle(abilities: scorch.merge(fire: BattleFixtures.abilities[:fire])) }.to raise_error(ArgumentError, /unknown type fire/)
      expect { world_battle(terrain: "grass") }.to raise_error(ArgumentError, /unknown terrain/)
      expect { world_battle(enemies: [ blob.first.merge(types: %w[grass]) ]) }.to raise_error(ArgumentError, /unknown types/)
      expect { world_battle(types: { "chart" => {} }) }.to raise_error(ArgumentError, /at least one type/)
      expect { world_battle(types: { "chart" => { "plain" => { "odd" => 200 } } }) }.to raise_error(ArgumentError, /unknown type odd/)
    end

    it "works with a single type, where everything lands as it is" do
      one = { "chart" => { "normal" => {} } }
      state = build_battle(seed: 2, party: [ mage.first.merge(abilities: %w[zap]) ], enemies: [ blob.first.merge(types: %w[normal]) ],
                           abilities: { zap: { name: "Zap", kind: "magic", target: "single_enemy", cost: { mp: 0 },
                                               effects: [ { primitive: "elemental", type: "normal", power: 20 } ] } }, types: one)
      _, events = apply(state, command("mage", "zap", "blob"))
      expect(of_type(events, :damage).find { |e| e["actor"] == "mage" }).to include("effectiveness" => 100)
    end

    it "plays battles stored before worlds had types on the base world's chart" do
      old = build_battle.except("types")
      expect { full_round(old) }.not_to raise_error
    end
  end
end
