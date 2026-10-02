# frozen_string_literal: true

require "spec_helper"

RSpec.describe Story::Coverage do
  let(:rows) do
    [ { "text" => "A town.", "when" => "town" },
      { "text" => "A town by night.", "when" => "town, night" },
      { "text" => "Never at all.", "when" => "town, dungeon" },
      { "text" => "Smoke again.", "when" => "town, smoke_seen" },
      { "text" => "A lamp {color|lit}.", "when" => "lamps >= 2, mood = grim" } ]
  end
  let(:moments) do
    [ { "town" => true }, { "town" => true, "night" => true }, { "dungeon" => true }, { "town" => true, "smoke_seen" => "yes" } ]
  end

  it "counts what fits and what wins over many moments, and which moments nothing fits" do
    report = described_class.run(rows, moments)
    expect(report["moments"]).to eq(4)
    expect(report["empty"]).to eq([ { "dungeon" => true } ])
    expect(report["rows"].map { |r| [ r["fits"], r["wins"] ] }).to eq([ [ 3, 1 ], [ 1, 1 ], [ 0, 0 ], [ 1, 1 ], [ 0, 0 ] ])
    expect(report["rows"][0]["beaten_by"]).to eq(1 => 1, 3 => 1) # the town row loses to the night row and the smoke row
  end

  it "groups moments into slots, the emptiest first" do
    slots = described_class.slots(moments, [ moments[2] ]) { |facts| facts["dungeon"] ? "dungeon" : "town" }
    expect(slots).to eq("dungeon" => [ 1, 1 ], "town" => [ 3, 0 ])
  end

  it "ranks every row that fits a moment, the most specific first" do
    ranked = described_class.rank(rows, { "town" => true, "night" => true })
    expect(ranked.map { |c| [ c["index"], c["score"] ] }).to eq([ [ 1, 2 ], [ 0, 1 ] ])
  end

  it "knows what the rows ask about, and what they compare it to" do
    expect(described_class.asked(rows)).to include("smoke_seen" => { "values" => [], "numbers" => false },
                                                   "lamps" => { "values" => [], "numbers" => true },
                                                   "mood" => { "values" => [ "grim" ], "numbers" => false })
  end
end
