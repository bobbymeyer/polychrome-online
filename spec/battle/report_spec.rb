# frozen_string_literal: true

RSpec.describe Battle::Report do
  def unit(id, name, side, hp, max_hp = hp)
    { "id" => id, "name" => name, "side" => side, "hp" => hp, "stats" => { "max_hp" => max_hp } }
  end

  def row(report, id) = report["units"].find { |r| r["id"] == id }

  describe "from a log written by hand" do
    let(:initial) do
      { "round" => 1, "status" => "input", "abilities" => { "fire" => { "id" => "fire", "name" => "Fire" }, "attack" => { "id" => "attack", "name" => "Attack" } },
        "units" => [ unit("bartz", "Bartz", "party", 100), unit("lenna", "Lenna", "party", 40, 100), unit("goblin", "Goblin", "enemy", 30) ] }
    end
    let(:final) do
      initial.merge("status" => "victory", "round" => 2,
                    "units" => [ unit("bartz", "Bartz", "party", 82, 100), unit("lenna", "Lenna", "party", 100), unit("goblin", "Goblin", "enemy", 0) ])
    end
    let(:events) do
      [
        { "type" => "round_start", "round" => 1 },
        { "type" => "turn_start", "unit" => "bartz" },
        { "type" => "cast", "actor" => "bartz", "ability" => "fire", "targets" => [ "goblin" ], "mp_cost" => 4 },
        { "type" => "crit", "actor" => "bartz", "target" => "goblin" },
        { "type" => "damage", "target" => "goblin", "amount" => 12, "hp" => 18, "actor" => "bartz" },
        { "type" => "turn_end", "unit" => "bartz" },
        { "type" => "turn_start", "unit" => "goblin" },
        { "type" => "attack", "actor" => "goblin", "ability" => "attack", "targets" => [ "bartz" ], "mp_cost" => 0 },
        { "type" => "damage", "target" => "bartz", "amount" => 15, "hp" => 85 }, # no actor on the event: the goblin's turn
        { "type" => "counter", "actor" => "bartz", "target" => "goblin" },
        { "type" => "damage", "target" => "goblin", "amount" => 8, "hp" => 10, "actor" => "bartz" },
        { "type" => "damage", "target" => "goblin", "amount" => 3, "hp" => 7, "status" => "poison" },
        { "type" => "turn_end", "unit" => "goblin" },
        { "type" => "turn_start", "unit" => "lenna" },
        { "type" => "item_used", "actor" => "lenna", "item" => "potion", "name" => "Potion", "targets" => [ "lenna" ] },
        { "type" => "heal", "target" => "lenna", "amount" => 100, "hp" => 100 }, # 60 of it lands
        { "type" => "turn_end", "unit" => "lenna" },
        { "type" => "round_start", "round" => 2 },
        { "type" => "turn_start", "unit" => "bartz" },
        { "type" => "attack", "actor" => "bartz", "ability" => "attack", "targets" => [ "goblin" ], "mp_cost" => 0 },
        { "type" => "miss", "actor" => "bartz", "target" => "goblin", "reason" => "evaded" },
        { "type" => "turn_end", "unit" => "bartz" },
        { "type" => "turn_start", "unit" => "lenna" },
        { "type" => "attack", "actor" => "lenna", "ability" => "attack", "targets" => [ "goblin" ], "mp_cost" => 0 },
        { "type" => "damage", "target" => "goblin", "amount" => 50, "hp" => 0, "actor" => "lenna" }, # 7 of it lands
        { "type" => "ko", "target" => "goblin" },
        { "type" => "turn_end", "unit" => "lenna" },
        { "type" => "victory", "rewards" => {} }
      ]
    end
    let(:report) { described_class.build(initial, events, final) }

    it "counts what landed, for whoever did it" do
      expect(row(report, "bartz")).to include("dealt" => 20, "taken" => 15, "actions" => 2, "mp_spent" => 4, "crits" => 1, "misses" => 1, "kos" => 0, "hp" => 82)
      expect(row(report, "bartz")["abilities"]).to eq("Attack" => 1, "Fire" => 1) # the counter isn't an action of its own
      expect(row(report, "lenna")).to include("dealt" => 7, "healed" => 60, "kos" => 1, "actions" => 2)
      expect(row(report, "lenna")["abilities"]).to eq("Attack" => 1, "Potion" => 1)
      expect(row(report, "goblin")).to include("dealt" => 15, "taken" => 30, "actions" => 1)
    end

    it "keeps a status's damage to itself, and adds up by round and by side" do
      expect(report["by_status"]).to eq("poison" => 3)
      expect(report["by_round"]).to eq([ { "round" => 1, "party" => 20, "enemy" => 15 }, { "round" => 2, "party" => 7, "enemy" => 0 } ])
      expect(report["sides"]["party"]).to include("dealt" => 27, "taken" => 15, "kos" => 1)
      expect(report).to include("result" => "victory", "rounds" => 2, "turns" => 5)
      expect(report["units"].map { |r| r["id"] }).to eq(%w[bartz lenna goblin]) # the party first
    end
  end

  describe "from battles the resolver plays out" do
    def play_out(seed)
      state = build_battle(seed: seed)
      initial = Marshal.load(Marshal.dump(state))
      log = []
      40.times do
        break unless state["status"] == "input"

        state, events = full_round(state)
        log += events
      end
      [ initial, log, state ]
    end

    it "accounts for every point of damage, and ends with every unit's HP" do
      [ 1, 3, 7, 11 ].each do |seed|
        initial, log, final = play_out(seed)
        report = described_class.build(initial, log, final)
        taken = report["units"].sum { |r| r["taken"] }
        dealt = report["units"].sum { |r| r["dealt"] }
        expect(dealt + report["by_status"].values.sum).to eq(taken), "seed #{seed}"
        expect(report["by_round"].sum { |r| r["party"] + r["enemy"] }).to be <= dealt
        final["units"].each { |u| expect(row(report, u["id"])["hp"]).to eq(u["hp"]) }
        expect(report["sides"]["party"]["kos"]).to be <= final["units"].count { |u| u["side"] == "enemy" }
        expect(report["result"]).to eq(final["status"])
      end
    end
  end
end
