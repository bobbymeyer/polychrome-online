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

  it "is the same every time for the same states" do
    states = (1..4).map { |seed| build_battle(seed: seed) }
    expect(described_class.run(states)).to eq(described_class.run(states))
  end
end
