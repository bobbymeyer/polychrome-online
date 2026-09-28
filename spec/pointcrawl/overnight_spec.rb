# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/pointcrawl"

RSpec.describe Pointcrawl::Overnight do
  # Varn (town) — Tule (town) by a dangerous road; Tule — the marsh — the abbey (a dungeon).
  let(:world) do
    {
      "places" => [ { "id" => 1, "name" => "Varn", "town" => true, "settled" => true },
                    { "id" => 2, "name" => "Tule", "town" => true, "settled" => true },
                    { "id" => 3, "name" => "Greymere", "town" => false, "settled" => false },
                    { "id" => 4, "name" => "The Abbey", "town" => false, "settled" => true } ],
      "roads" => [ { "from" => 1, "to" => 2, "state" => "dangerous" }, { "from" => 2, "to" => 3, "state" => "open" },
                   { "from" => 3, "to" => 4, "state" => "open" } ],
      "clocks" => [ 10, 11 ],
      "rumours" => [ { "id" => 5, "reached" => [ 1 ], "age" => 0 }, { "id" => 6, "reached" => [ 1 ], "age" => 6 } ],
      "antagonists" => [ { "id" => 7, "name" => "Mara", "at" => 2 } ],
      "prices" => { 1 => 20, 2 => 0 }
    }
  end

  def night(seed, state = world) = described_class.run(state, seed)
  def kinds(happenings, kind) = happenings.select { |h| h["kind"] == kind }

  it "is the same night from the same dice, and a different one from others" do
    expect(night(3)).to eq(night(3))
    expect((1..30).map { |s| night(s).last }.uniq.size).to be > 5
  end

  it "moves rumours a road a day, and lets old ones fade" do
    happenings = night(1).last
    expect(kinds(happenings, "spread")).to eq([ { "kind" => "spread", "rumour" => 5, "to" => [ 2 ] } ])
    expect(kinds(happenings, "fade")).to eq([ { "kind" => "fade", "rumour" => 6 } ])
    blocked = world.merge("roads" => [ { "from" => 1, "to" => 2, "state" => "blocked" } ])
    expect(kinds(night(1, blocked).last, "spread")).to be_empty
  end

  it "sends an antagonist somewhere with people, past the marsh if need be, about half the time" do
    moves = (1..200).flat_map { |s| kinds(night(s).last, "moved") }
    expect(moves.size).to be_within(30).of(100)
    expect(moves.map { |m| m["to"] }.uniq).to contain_exactly(1, 4)
    expect(moves).to all(include("npc" => 7, "name" => "Mara", "from" => 2))
  end

  it "loses caravans only on dangerous roads between towns, and moves prices with them" do
    nights = (1..300).map { |s| night(s).last }
    caravans = nights.flat_map { |h| kinds(h, "caravan") }
    expect(caravans.map { |c| [ c["from"], c["to"] ] }.uniq).to eq([ [ 1, 2 ] ])
    expect(caravans.size).to be_within(25).of(45)
    struck = nights.find { |h| kinds(h, "caravan").any? }
    expect(kinds(struck, "price")).to contain_exactly({ "kind" => "price", "place" => 1, "shift" => 30 },
                                                      { "kind" => "price", "place" => 2, "shift" => 15 })
    calm = nights.find { |h| kinds(h, "caravan").empty? }
    expect(kinds(calm, "price")).to eq([ { "kind" => "price", "place" => 1, "shift" => 15 } ]) # easing back
  end

  it "ticks clocks that tick now and then, some nights" do
    ticks = (1..200).flat_map { |s| kinds(night(s).last, "clock") }
    expect(ticks.map { |t| t["clock"] }.tally.values).to all(be_within(30).of(70))
  end

  it "draws the same for everyone else whatever the rumours do" do
    quiet = world.merge("rumours" => [])
    expect(kinds(night(9, quiet).last, "moved")).to eq(kinds(night(9).last, "moved"))
  end
end
