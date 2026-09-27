# frozen_string_literal: true

RSpec.describe Stats::Check do
  def chance(value, difficulty = "normal", level: 5)
    described_class.chance(stat_value: value, stat: "agi", level: level, difficulty: difficulty)
  end

  it "gives a typical character an even chance at normal, and moves with the stat and the difficulty" do
    typical = Stats::Growth.base_stats(5)["agi"]
    expect(chance(typical)).to eq(50)
    expect(chance(typical + 3)).to be > 50
    expect(chance(typical, "easy")).to be > chance(typical, "normal")
    expect(chance(typical, "heroic")).to be < chance(typical, "hard")
  end

  it "never makes anything certain" do
    expect(chance(999)).to eq(95)
    expect(chance(0, "heroic")).to eq(5)
  end

  it "rolls 1–100 from the RNG it's given, the same every time from the same state" do
    results = Array.new(2) { described_class.roll(stat_value: 12, stat: "agi", level: 5, difficulty: "normal", rng: Battle::Rng.new(42)) }
    expect(results.first).to eq(results.last)
    expect(results.first["roll"]).to be_between(1, 100)
    expect(results.first["success"]).to eq(results.first["roll"] <= results.first["chance"])
  end

  it "refuses stats and difficulties it doesn't know" do
    expect { chance(10, "impossible") }.to raise_error(ArgumentError)
    expect { described_class.chance(stat_value: 1, stat: "atk", level: 5, difficulty: "easy") }.to raise_error(ArgumentError)
  end
end
