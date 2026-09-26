# frozen_string_literal: true

RSpec.describe Pointcrawl::Encounters do
  let(:entries) do
    [ { "weight" => 3, "monsters" => { "goblin" => 3 } },
      { "weight" => 1, "monsters" => { "wolf" => 2 } } ]
  end

  it "always meets something on a dangerous edge, never on a blocked one" do
    state = 1
    50.times do
      state, monsters = described_class.roll(state, entries, "dangerous")
      expect(monsters).not_to be_nil
    end
    expect(described_class.roll(state, entries, "blocked").last).to be_nil
  end

  it "meets something on an open edge about a quarter of the time" do
    state = 7
    hits = Array.new(2000) { state, monsters = described_class.roll(state, entries, "open"); monsters }.compact.size
    expect(hits).to be_within(100).of(500)
  end

  it "respects the weights" do
    state = 3
    picks = Array.new(4000) { state, monsters = described_class.roll(state, entries, "dangerous"); monsters.keys.first }.tally
    expect(picks["goblin"]).to be_within(150).of(3000)
    expect(picks["wolf"]).to be_within(150).of(1000)
  end

  it "is deterministic and consumes the same amount of randomness hit or miss" do
    expect(described_class.roll(42, entries, "open")).to eq(described_class.roll(42, entries, "open"))
    open_state, = described_class.roll(42, entries, "open")
    blocked_state, = described_class.roll(42, entries, "blocked")
    expect(open_state).to eq(blocked_state)
  end

  it "meets nothing from an empty table" do
    expect(described_class.roll(1, [], "dangerous").last).to be_nil
  end
end
