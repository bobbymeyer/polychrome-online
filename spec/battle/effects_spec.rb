# frozen_string_literal: true

# Formula-level specs: each primitive driven with a scripted RNG so the
# arithmetic is pinned exactly.
RSpec.describe Battle::Effects do
  # goblin_a is given a deep HP pool so single hits never end in a KO.
  let(:state) do
    state = build_battle(enemies: BattleFixtures.goblins(2) + BattleFixtures.ogre)
    with_unit(state, "goblin_a", stats: unit(state, "goblin_a")["stats"].merge("max_hp" => 500), hp: 500)
  end
  let(:rng) { ScriptedRng.new }
  let(:ctx) { Battle::Context.new(state, rng: rng) }
  let(:bartz) { ctx.unit("bartz") }
  let(:vivi) { ctx.unit("vivi") }
  let(:rosa) { ctx.unit("rosa") }
  let(:goblin) { ctx.unit("goblin_a") }
  let(:ogre) { ctx.unit("ogre") }

  def effect(primitive, **params)
    { "primitive" => primitive }.merge(params.transform_keys(&:to_s))
  end

  describe "physical" do
    # bartz: atk 14 + str 14 = 28; goblin def 3, agi 8 vs bartz agi 12
    it "computes (atk + str) * power, variance, then def mitigation" do
      rng = ScriptedRng.new(0, 99, 31) # hit, no crit, max variance
      ctx = Battle::Context.new(state, rng: rng)
      described_class.apply(ctx, ctx.unit("bartz"), ctx.unit("goblin_a"), effect("physical", power: 100))

      damage = of_type(ctx.events, :damage).sole
      expect(damage).to include("target" => "goblin_a", "amount" => 28 * 255 / 256 * 100 / 103, "crit" => false)
      expect(ctx.unit("goblin_a")["hp"]).to eq(500 - damage["amount"])
    end

    it "scales with power" do
      rng = ScriptedRng.new(0, 99, 31)
      ctx = Battle::Context.new(state, rng: rng)
      described_class.apply(ctx, ctx.unit("bartz"), ctx.unit("goblin_a"), effect("physical", power: 200))
      expect(of_type(ctx.events, :damage).sole["amount"]).to eq(56 * 255 / 256 * 100 / 103)
    end

    it "doubles on a crit and announces it first" do
      rng = ScriptedRng.new(0, 0, 31)
      ctx = Battle::Context.new(state, rng: rng)
      described_class.apply(ctx, ctx.unit("bartz"), ctx.unit("goblin_a"), effect("physical"))
      expect(types(ctx.events)).to eq(%w[crit damage])
      expect(ctx.events.last["amount"]).to eq(28 * 255 / 256 * 100 / 103 * 2)
    end

    it "misses when the hit roll fails" do
      rng = ScriptedRng.new(99)
      ctx = Battle::Context.new(state, rng: rng)
      described_class.apply(ctx, ctx.unit("bartz"), ctx.unit("goblin_a"), effect("physical"))
      expect(ctx.events).to eq([ { "type" => "miss", "actor" => "bartz", "target" => "goblin_a", "reason" => "evaded", "roll" => 100, "needed" => 97 } ])
    end

    it "halves hit chance when blind" do
      bartz["statuses"] << { "kind" => "blind", "turns" => 2 }
      expect(described_class.hit_chance(ctx, bartz, goblin)).to eq(97 / 2)
    end

    it "always hits a sleeping target, still drawing the hit roll, and wakes it" do
      goblin["statuses"] << { "kind" => "sleep", "turns" => 2 }
      rng = ScriptedRng.new(99, 99, 0)
      ctx = Battle::Context.new(state, rng: rng)
      described_class.apply(ctx, ctx.unit("bartz"), ctx.unit("goblin_a"), effect("physical"))
      expect(types(ctx.events)).to eq(%w[damage status_expired])
      expect(ctx.events.last).to include("status" => "sleep", "reason" => "woke")
      expect(rng.draws).to eq(3)
    end

    it "halves damage against a defending target" do
      goblin["defending"] = true
      rng = ScriptedRng.new(0, 99, 31)
      ctx = Battle::Context.new(state, rng: rng)
      described_class.apply(ctx, ctx.unit("bartz"), ctx.unit("goblin_a"), effect("physical"))
      expect(ctx.events.last["amount"]).to eq(28 * 255 / 256 * 100 / 103 / 2)
    end

    it "always deals at least 1" do
      goblin["stats"]["def"] = 999
      bartz["stats"]["atk"] = 0
      bartz["stats"]["str"] = 1
      described_class.apply(ctx, bartz, goblin, effect("physical"))
      expect(of_type(ctx.events, :damage).sole["amount"]).to eq(1)
    end

    it "uses buffed stats" do
      bartz["buffs"] << { "stat" => "str", "amount" => 100, "turns" => 2 }
      rng = ScriptedRng.new(0, 99, 31)
      ctx = Battle::Context.new(state, rng: rng)
      described_class.apply(ctx, ctx.unit("bartz"), ctx.unit("goblin_a"), effect("physical"))
      expect(ctx.events.last["amount"]).to eq(42 * 255 / 256 * 100 / 103)
    end

    it "knocks out at zero HP and clears statuses and buffs" do
      goblin["hp"] = 1
      goblin["statuses"] << { "kind" => "poison", "turns" => 3 }
      goblin["buffs"] << { "stat" => "def", "amount" => 50, "turns" => 3 }
      described_class.apply(ctx, bartz, goblin, effect("physical"))
      expect(types(ctx.events)).to include("ko")
      expect(goblin).to include("hp" => 0, "statuses" => [], "buffs" => [])
    end
  end

  describe "elemental" do
    # vivi mag 18: power 20 * (18 + 16) / 16 = 42
    let(:fire) { effect("elemental", type: "fire", power: 20) }

    def cast(target_id, spell = fire)
      rng = ScriptedRng.new(31)
      ctx = Battle::Context.new(state, rng: rng)
      described_class.apply(ctx, ctx.unit("vivi"), ctx.unit(target_id), spell)
      ctx
    end

    it "doubles against weakness" do
      # goblin mdef 2
      expect(cast("goblin_a").events.sole).to include("type" => "damage", "amount" => 42 * 255 / 256 * 100 / 102 * 2,
                                                      "damage_type" => "fire", "effectiveness" => 200)
    end

    it "halves against resistance" do
      expect(cast("ogre").events.sole["amount"]).to eq(42 * 255 / 256 * 100 / 106 / 2)
    end

    it "heals on absorb" do
      state["units"].find { |u| u["id"] == "ogre" }["hp"] = 100
      ctx = cast("ogre", effect("elemental", type: "ice", power: 20))
      expect(ctx.events.sole).to include("type" => "heal", "absorbed" => true, "hp" => 100 + 41 * 100 / 106)
    end

    it "follows the type chart, types multiplying, and a typeless move is always neutral" do
      goblin = state["units"].find { |u| u["id"] == "goblin_a" }
      goblin["affinities"] = {}
      goblin["types"] = %w[grass]
      expect(cast("goblin_a").events.sole).to include("effectiveness" => 200)
      goblin["types"] = %w[grass bug]
      expect(cast("goblin_a").events.sole).to include("effectiveness" => 400)
      goblin["types"] = %w[water]
      expect(cast("goblin_a").events.sole).to include("effectiveness" => 50)
      goblin["types"] = %w[ground]
      expect(cast("goblin_a", effect("elemental", type: "electric", power: 20)).events.sole).to include("type" => "miss", "reason" => "immune")
      goblin["types"] = %w[ghost]
      ctx = Battle::Context.new(state, rng: ScriptedRng.new(31))
      described_class.apply(ctx, ctx.unit("bartz"), ctx.unit("goblin_a"), effect("physical"))
      expect(ctx.events.last).to include("type" => "damage")
      expect(ctx.events.last).not_to have_key("effectiveness")
      ctx = Battle::Context.new(state, rng: ScriptedRng.new(31))
      described_class.apply(ctx, ctx.unit("bartz"), ctx.unit("goblin_a"), effect("physical", type: "normal"))
      expect(ctx.events.last).to include("type" => "miss", "reason" => "immune", "damage_type" => "normal")
    end

    it "keeps poison types from being poisoned, and electric types from paralysis" do
      goblin = state["units"].find { |u| u["id"] == "goblin_a" }
      goblin["types"] = %w[poison]
      ctx = Battle::Context.new(state, rng: ScriptedRng.new(0))
      described_class.apply(ctx, ctx.unit("vivi"), ctx.unit("goblin_a"), effect("status", kind: "poison", chance: 100))
      expect(ctx.events.sole).to include("type" => "miss", "reason" => "immune", "status" => "poison")
    end

    it "misses on immunity without shifting the RNG stream" do
      goblin_state = state["units"].find { |u| u["id"] == "goblin_a" }
      goblin_state["affinities"] = { "fire" => "immune" }
      rng = ScriptedRng.new(31)
      ctx = Battle::Context.new(state, rng: rng)
      described_class.apply(ctx, ctx.unit("vivi"), ctx.unit("goblin_a"), fire)
      expect(ctx.events.sole).to include("type" => "miss", "reason" => "immune")
      expect(rng.draws).to eq(1)
    end

    it "does not wake a sleeping target" do
      goblin_state = state["units"].find { |u| u["id"] == "goblin_a" }
      goblin_state["statuses"] << { "kind" => "sleep", "turns" => 2 }
      expect(types(cast("goblin_a").events)).to eq(%w[damage])
    end
  end

  describe "status" do
    it "lands at 100% regardless of spr" do
      described_class.apply(ctx, vivi, goblin, effect("status", kind: "poison", chance: 100, duration: 4))
      expect(ctx.events.sole).to include("type" => "status_applied", "status" => "poison", "turns" => 4)
      expect(goblin["statuses"]).to eq([ { "kind" => "poison", "turns" => 4 } ])
    end

    it "reduces chance by the target's spr" do
      # 70 * 100 / (100 + spr 10) = 63
      ctx = Battle::Context.new(state, rng: ScriptedRng.new(63))
      described_class.apply(ctx, ctx.unit("vivi"), ctx.unit("goblin_a"), effect("status", kind: "sleep", chance: 70))
      expect(ctx.events.sole).to include("type" => "miss", "reason" => "resisted")

      ctx = Battle::Context.new(state, rng: ScriptedRng.new(62))
      described_class.apply(ctx, ctx.unit("vivi"), ctx.unit("goblin_a"), effect("status", kind: "sleep", chance: 70))
      expect(ctx.events.sole).to include("type" => "status_applied")
    end

    it "does not apply spr resistance to allies" do
      ctx = Battle::Context.new(state, rng: ScriptedRng.new(69))
      described_class.apply(ctx, ctx.unit("rosa"), ctx.unit("bartz"), effect("status", kind: "haste", chance: 70))
      expect(ctx.events.sole["type"]).to eq("status_applied")
    end

    it "respects immunity" do
      described_class.apply(ctx, vivi, ogre, effect("status", kind: "sleep", chance: 100))
      expect(ctx.events.sole).to include("type" => "miss", "reason" => "immune")
      expect(ogre["statuses"]).to be_empty
    end

    it "refreshes rather than stacks" do
      described_class.apply(ctx, vivi, goblin, effect("status", kind: "poison", chance: 100, duration: 2))
      described_class.apply(ctx, vivi, goblin, effect("status", kind: "poison", chance: 100, duration: 5))
      described_class.apply(ctx, vivi, goblin, effect("status", kind: "poison", chance: 100, duration: 1))
      expect(goblin["statuses"]).to eq([ { "kind" => "poison", "turns" => 5 } ])
    end
  end

  describe "heal" do
    it "scales with mag and caps at max HP" do
      bartz["hp"] = 10
      ctx = Battle::Context.new(state, rng: ScriptedRng.new(31))
      described_class.apply(ctx, ctx.unit("rosa"), ctx.unit("bartz"), effect("heal", power: 25))
      amount = 25 * (16 + 16) / 16 * 255 / 256
      expect(ctx.events.sole).to include("type" => "heal", "amount" => amount, "hp" => 10 + amount)

      described_class.apply(ctx, ctx.unit("rosa"), ctx.unit("bartz"), effect("heal", power: 500))
      expect(ctx.unit("bartz")["hp"]).to eq(120)
    end
  end

  describe "drain" do
    it "damages the target and heals the caster by the HP actually taken" do
      vivi["hp"] = 10
      goblin["hp"] = 5
      described_class.apply(ctx, vivi, goblin, effect("drain", power: 20))
      expect(types(ctx.events)).to eq(%w[damage ko heal])
      expect(of_type(ctx.events, :heal).sole).to include("target" => "vivi", "amount" => 5, "drain" => true)
      expect(vivi["hp"]).to eq(15)
    end
  end

  describe "buff and debuff" do
    it "adds a signed percent modifier" do
      described_class.apply(ctx, bartz, bartz, effect("buff", stat: "str", amount: 50, duration: 3))
      described_class.apply(ctx, bartz, goblin, effect("debuff", stat: "def", amount: 50, duration: 2))
      expect(bartz["buffs"]).to eq([ { "stat" => "str", "amount" => 50, "turns" => 3 } ])
      expect(goblin["buffs"]).to eq([ { "stat" => "def", "amount" => -50, "turns" => 2 } ])
      expect(ctx.stat(bartz, "str")).to eq(21)
      expect(ctx.stat(goblin, "def")).to eq(1)
    end

    it "replaces same-direction modifiers but keeps opposing ones" do
      described_class.apply(ctx, bartz, bartz, effect("buff", stat: "str", amount: 50, duration: 3))
      described_class.apply(ctx, bartz, bartz, effect("buff", stat: "str", amount: 20, duration: 5))
      described_class.apply(ctx, bartz, bartz, effect("debuff", stat: "str", amount: 10, duration: 1))
      expect(bartz["buffs"]).to contain_exactly(
        { "stat" => "str", "amount" => 20, "turns" => 5 },
        { "stat" => "str", "amount" => -10, "turns" => 1 }
      )
    end
  end

  describe "revive" do
    it "restores a fallen unit to a fraction of max HP" do
      ctx.knock_out(bartz)
      described_class.apply(ctx, rosa, bartz, effect("revive", fraction: 25))
      expect(bartz["hp"]).to eq(30)
      expect(ctx.events.last).to include("type" => "revive", "hp" => 30)
    end

    it "never revives to 0" do
      ctx.knock_out(bartz)
      described_class.apply(ctx, rosa, bartz, effect("revive", fraction: 0))
      expect(bartz["hp"]).to eq(1)
    end

    it "does nothing to the living" do
      described_class.apply(ctx, rosa, bartz, effect("revive", fraction: 50))
      expect(ctx.events.sole).to include("type" => "miss", "reason" => "not_ko")
    end
  end

  describe "steal" do
    let(:state) do
      drops = [ { "item" => "potion", "chance" => 30, "name" => "Potion" }, { "item" => "dagger", "chance" => 10, "name" => "Dagger" } ]
      with_unit(build_battle(enemies: BattleFixtures.goblins(2)), "goblin_a", drops: drops)
    end

    it "takes one weighted drop, once, and keeps it in the state" do
      ctx = Battle::Context.new(state, rng: ScriptedRng.new(0, 35)) # succeeds; 35 falls past potion's 30
      described_class.apply(ctx, ctx.unit("bartz"), ctx.unit("goblin_a"), effect("steal", chance: 50))
      expect(ctx.events.sole).to include("type" => "steal", "actor" => "bartz", "target" => "goblin_a", "item" => "dagger", "name" => "Dagger")
      expect(ctx.state["stolen"]).to eq([ "dagger" ])

      described_class.apply(ctx, ctx.unit("bartz"), ctx.unit("goblin_a"), effect("steal"))
      expect(ctx.events.last).to include("type" => "miss", "reason" => "nothing_to_steal")
    end

    it "draws the same whether or not it works, and can fail" do
      rng = ScriptedRng.new(99, 0)
      ctx = Battle::Context.new(state, rng: rng)
      described_class.apply(ctx, ctx.unit("bartz"), ctx.unit("goblin_a"), effect("steal", chance: 50))
      expect(ctx.events.sole).to include("type" => "miss", "reason" => "steal_failed")
      expect(rng.draws).to eq(2)
      expect(ctx.state["stolen"]).to be_nil
    end

    it "finds nothing on a foe that drops nothing, without drawing" do
      rng = ScriptedRng.new
      ctx = Battle::Context.new(with_unit(state, "goblin_b", drops: []), rng: rng)
      described_class.apply(ctx, ctx.unit("bartz"), ctx.unit("goblin_b"), effect("steal"))
      expect(ctx.events.sole).to include("reason" => "nothing_to_steal")
      expect(rng.draws).to eq(0)
    end
  end

  describe "scan" do
    it "reports affinities, immunities and HP, without drawing" do
      rng = ScriptedRng.new
      ctx = Battle::Context.new(state, rng: rng)
      described_class.apply(ctx, ctx.unit("rosa"), ctx.unit("ogre"), effect("scan"))
      expect(ctx.events.sole).to include("type" => "scan", "target" => "ogre", "types" => [ "normal" ], "affinities" => ctx.unit("ogre")["affinities"],
                                         "status_immune" => ctx.unit("ogre")["status_immune"], "hp" => ctx.unit("ogre")["hp"])
      expect(rng.draws).to eq(0)
    end
  end

  describe "escape" do
    it "ends the battle when escapable" do
      described_class.apply(ctx, bartz, bartz, effect("escape"))
      expect(ctx.events.sole).to include("type" => "flee", "success" => true)
      expect(ctx.state["status"]).to eq("fled")
    end

    it "fails when the battle forbids escape" do
      state["escapable"] = false
      described_class.apply(ctx, bartz, bartz, effect("escape"))
      expect(ctx.events.sole).to include("type" => "flee", "success" => false, "reason" => "no_escape")
      expect(ctx.over?).to be(false)
    end
  end

  describe ".upkeep" do
    it "deals poison damage of 1/16 max HP, then ticks durations" do
      bartz["statuses"] << { "kind" => "poison", "turns" => 2 }
      described_class.upkeep(ctx, bartz)
      expect(ctx.events.sole).to include("type" => "damage", "amount" => 7, "status" => "poison")
      expect(bartz["statuses"]).to eq([ { "kind" => "poison", "turns" => 1 } ])
    end

    it "expires statuses and buffs whose duration runs out" do
      bartz["statuses"] << { "kind" => "silence", "turns" => 1 }
      bartz["buffs"] << { "stat" => "str", "amount" => 50, "turns" => 1 }
      described_class.upkeep(ctx, bartz)
      expect(types(ctx.events)).to eq(%w[status_expired buff_expired])
      expect(bartz["statuses"]).to be_empty
      expect(bartz["buffs"]).to be_empty
    end

    it "stops at a poison KO" do
      bartz["hp"] = 3
      bartz["statuses"] << { "kind" => "poison", "turns" => 1 }
      described_class.upkeep(ctx, bartz)
      expect(types(ctx.events)).to eq(%w[damage ko])
    end
  end
end
