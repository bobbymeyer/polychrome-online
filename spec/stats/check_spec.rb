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

  it "rolls 1–100 from the RNG it's given, the same every time from the same state, and adds each modifier in turn" do
    results = Array.new(2) do
      described_class.roll(stat_value: 15, stat: "agi", level: 5, difficulty: "hard", rng: Battle::Rng.new(42),
                           bonuses: [ { "label" => "Knight", "amount" => 15 }, { "label" => "Cliffside", "amount" => 0 } ])
    end
    expect(results.first).to eq(results.last)
    result = results.first
    expect(result["roll"]).to be_between(1, 100)
    expect(result["needed"]).to eq(66)
    expect(result["modifiers"]).to eq([ { "label" => "agi", "amount" => described_class.stat_modifier(stat_value: 15, stat: "agi", level: 5) },
                                        { "label" => "Knight", "amount" => 15 } ]) # a bonus of nothing isn't a step
    typical = Stats::Growth.base_stats(5)["agi"]
    expect(described_class.roll(stat_value: typical, stat: "agi", level: 5, difficulty: "normal", rng: Battle::Rng.new(1))["modifiers"]).to eq([])
    expect(result["total"]).to eq(result["roll"] + result["modifiers"].sum { |m| m["amount"] })
    expect(result["success"]).to eq(result["total"] >= 66)
  end

  it "lets the die have the last word: a natural 1–5 fails and a natural 96–100 succeeds, whatever the modifiers" do
    low = described_class.roll(stat_value: 999, stat: "str", level: 5, difficulty: "easy", rng: ScriptedRng.new(2)) # rolls a 3
    expect(low).to include("roll" => 3, "success" => false)
    expect(low["total"]).to be > 36
    high = described_class.roll(stat_value: 0, stat: "str", level: 5, difficulty: "heroic", rng: ScriptedRng.new(97)) # rolls a 98
    expect(high).to include("roll" => 98, "success" => true)
    expect(high["total"]).to be < 81
  end

  it "has the same odds as it says: the chance is how often the total reaches what's needed" do
    typical = Stats::Growth.base_stats(5)["agi"]
    hits = (0...100).count { |n| described_class.roll(stat_value: typical + 4, stat: "agi", level: 5, difficulty: "hard", rng: ScriptedRng.new(n), bonus: 15)["success"] }
    expect(hits).to eq(chance(typical + 4, "hard") + 15)
  end

  it "refuses stats and difficulties it doesn't know" do
    expect { chance(10, "impossible") }.to raise_error(ArgumentError)
    expect { described_class.chance(stat_value: 1, stat: "atk", level: 5, difficulty: "easy") }.to raise_error(ArgumentError)
  end
end
