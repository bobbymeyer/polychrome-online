# frozen_string_literal: true

require_relative "../../lib/duel_meter"

RSpec.describe DuelMeter do
  it "puts each round's target in the same place for the same duel, somewhere new each round" do
    zones = (1..3).map { |round| described_class.zone(42, round) }
    expect((1..3).map { |round| described_class.zone(42, round) }).to eq(zones)
    expect(zones.map { |z| z["center"] }.uniq.size).to be > 1
    expect(described_class.zone(43, 1)).not_to eq(zones.first)
  end

  it "narrows the bands round by round, and keeps them on the meter" do
    zones = (1..3).map { |round| described_class.zone(7, round) }
    expect(zones.map { |z| [ z["good"], z["okay"] ] }).to eq([ [ 5, 10 ], [ 4, 7 ], [ 3, 4 ] ])
    (1..200).each do |seed|
      (1..3).each do |round|
        zone = described_class.zone(seed, round)
        reach = described_class::PERFECT + zone["good"] + zone["okay"]
        expect(zone["center"] - reach).to be >= 0
        expect(zone["center"] + reach).to be <= described_class::LENGTH
      end
    end
    expect { described_class.zone(1, 4) }.to raise_error(ArgumentError)
  end

  it "scores a 1-unit perfect, then good, then okay, then a miss" do
    zone = { "center" => 100, "good" => 5, "okay" => 10 }
    expect(described_class.grade(zone, 100.4)).to eq("perfect")
    expect(described_class.grade(zone, 99.5)).to eq("perfect")
    expect(described_class.grade(zone, 101)).to eq("good")
    expect(described_class.grade(zone, 94.5)).to eq("good")
    expect(described_class.grade(zone, 94.4)).to eq("okay")
    expect(described_class.grade(zone, 115.5)).to eq("okay")
    expect(described_class.grade(zone, 116)).to eq("miss")
    expect(%w[perfect good okay miss].map { |g| described_class.points(g) }).to eq([ 3, 2, 1, 0 ])
  end

  it "takes only a position on the meter, to a tenth" do
    expect(described_class.position("123.456")).to eq(123.5)
    expect { described_class.position("-1") }.to raise_error(ArgumentError)
    expect { described_class.position("301") }.to raise_error(ArgumentError)
    expect { described_class.position("NaN") }.to raise_error(ArgumentError)
    expect { described_class.position("far") }.to raise_error(ArgumentError)
  end

  it "adds up the rounds, and calls level totals satisfaction" do
    rounds = [ { "swings" => { "character" => { "points" => 3 }, "gm" => { "points" => 1 } } },
               { "swings" => { "character" => { "points" => 0 }, "gm" => { "points" => 2 } } } ]
    expect(described_class.totals(rounds)).to eq("character" => 3, "gm" => 3)
    expect(described_class.result("character" => 3, "gm" => 3)).to eq("satisfaction")
    expect(described_class.result("character" => 4, "gm" => 3)).to eq("character")
    expect(described_class.result("character" => 1, "gm" => 3)).to eq("gm")
  end
end
