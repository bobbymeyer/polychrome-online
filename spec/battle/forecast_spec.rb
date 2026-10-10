# frozen_string_literal: true

RSpec.describe Battle::Forecast do
  it "plays a fight out from several seeds and says how it tends to go" do
    easy = described_class.run((1..8).map { |seed| build_battle(seed: seed, enemies: BattleFixtures.goblins(1)) })
    hard = described_class.run((1..8).map { |seed| build_battle(seed: seed, party: [ BattleFixtures.party[1] ], enemies: BattleFixtures.ogre) })

    expect(easy).to include("runs" => 8, "wins" => 8)
    expect(easy["hp_left"]).to be > hard["hp_left"]
    expect(hard["wins"]).to be < 8
    expect(easy["rounds"]).to be_positive
  end

  it "plays a sensible party: the fallen are raised and the badly hurt mended, and everyone else attacks" do
    state = build_battle(seed: 1)
    hurt = with_unit(state, "bartz", hp: 10)
    expect(described_class.sensible(hurt, "rosa")).to eq("kind" => "ability", "ability" => "cure", "target" => "bartz")
    fallen = with_unit(hurt, "locke", hp: 0)
    expect(described_class.sensible(fallen, "rosa")).to eq("kind" => "ability", "ability" => "raise", "target" => "locke")
    expect(described_class.sensible(state, "rosa")).to be_nil
    expect(described_class.sensible(hurt, "bartz")).to be_nil # nothing to mend with
  end

  it "with full tactics, spends MP on the hardest-hitting move: on all the foes when there are several, else the weakest" do
    many = build_battle(seed: 1, enemies: BattleFixtures.goblins(3))
    expect(described_class.sensible(many, "vivi")).to be_nil # the floor just attacks
    move = described_class.sensible(many, "vivi", tactics: "full")
    expect(many["abilities"][move["ability"]]["target"]).to eq("all_enemies")
    expect(move).not_to have_key("target")

    one = build_battle(seed: 1, enemies: BattleFixtures.goblins(1))
    single = described_class.sensible(one, "vivi", tactics: "full")
    expect(one["abilities"][single["ability"]]["target"]).to eq("single_enemy")
    expect(single["target"]).to eq(one["units"].find { |u| u["side"] == "enemy" }["id"])
    expect(described_class.sensible(with_unit(one, "vivi", mp: 0), "vivi", tactics: "full")).to be_nil # nothing to spend: attack
    expect(described_class.sensible(with_unit(one, "bartz", hp: 10), "rosa", tactics: "full")["ability"]).to eq("cure") # mending still comes first
  end

  it "chooses by the type chart: no spell at a foe it can't touch, the one it's weak to first" do
    one = build_battle(seed: 1, enemies: BattleFixtures.goblins(1))
    goblin = one["units"].find { |u| u["side"] == "enemy" }["id"]
    type_of = ->(state) { state["abilities"][described_class.sensible(state, "vivi", tactics: "full")["ability"]]["effects"].first["type"] }
    type = type_of.(one)

    immune = with_unit(one, goblin, affinities: { type => "immune" })
    move = described_class.sensible(immune, "vivi", tactics: "full") # another spell, or a plain Attack (nil)
    expect(move && immune["abilities"][move["ability"]]["effects"].first["type"]).not_to eq(type)

    others = unit(one, "vivi")["abilities"].filter_map { |slug| one["abilities"][slug] }
                                           .flat_map { |a| Array(a["effects"]).filter_map { |e| e["type"] } }.uniq - [ type ]
    weak = with_unit(one, goblin, affinities: { others.first => "weak" })
    expect(type_of.(weak)).to eq(others.first)
  end

  it "with full tactics, keeps a Guard up while the guard is fit to take the blows" do
    state = with_unit(build_battle(seed: 1), "bartz", abilities: %w[cover double_cut])
    expect(described_class.sensible(state, "bartz", tactics: "full")).to eq("kind" => "ability", "ability" => "cover")
    expect(described_class.sensible(state, "bartz")).to be_nil # the floor just attacks

    up = with_unit(state, "bartz", statuses: [ { "kind" => "cover", "turns" => 2 } ],
                                   last_command: { "kind" => "ability", "ability" => "cover" })
    move = described_class.sensible(up, "bartz", tactics: "full") # the guard's up: hit something, don't let the round repeat it
    expect(move).to include("kind" => "ability")
    expect(%w[attack double_cut]).to include(move["ability"])
    hurt = with_unit(state, "bartz", hp: unit(state, "bartz")["stats"]["max_hp"] / 3)
    expect(described_class.sensible(hurt, "bartz", tactics: "full")&.dig("ability")).not_to eq("cover")
  end

  it "says what MP is left, and with report: true, what every run came to" do
    states = (1..6).map { |seed| build_battle(seed: seed, enemies: BattleFixtures.goblins(3)) }
    floor = described_class.run(states)
    full = described_class.run(states, tactics: "full", report: true)

    expect(floor).not_to have_key("report")
    expect(full["mp_left"]).to be < floor["mp_left"]
    expect(full["rounds"]).to be <= floor["rounds"]
    expect(full["report"]["battles"].map { |b| b["name"] }).to eq((1..6).map { |i| "Run #{i}" })
    expect(full["report"]["battles"].map { |b| b["result"] }.count("victory")).to eq(full["wins"])
    expect(full["report"]["moves"].select { |m| m["side"] == "party" }.map { |m| m["name"] }).to include("Fira")
  end

  it "is the same every time for the same states" do
    states = (1..4).map { |seed| build_battle(seed: seed) }
    expect(described_class.run(states)).to eq(described_class.run(states))
  end
end
