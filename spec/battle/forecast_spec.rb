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

  it "is the same every time for the same states" do
    states = (1..4).map { |seed| build_battle(seed: seed) }
    expect(described_class.run(states)).to eq(described_class.run(states))
  end
end
