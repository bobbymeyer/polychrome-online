# frozen_string_literal: true

require "spec_helper"

RSpec.describe Battle::Field do
  let(:items) { Battle::State.normalize(BattleFixtures.items) }
  let(:party) { Battle::State.normalize(BattleFixtures.party) }
  let(:bartz) { party.find { |u| u["id"] == "bartz" }.merge("hp" => 30) }
  let(:rosa) { party.find { |u| u["id"] == "rosa" }.merge("hp" => 80) }
  let(:rng) { Battle::Rng.seed_state(9) }

  it "heals with the same formula as in battle, from the RNG state it's given" do
    hp, events, next_rng = described_class.use_item(items["potion"], user: rosa, target: bartz, rng: rng)
    expect(hp).to be > 30
    expect(events.map { |e| e["type"] }).to eq([ "heal" ])
    expect(next_rng).not_to eq(rng)
    expect(described_class.use_item(items["potion"], user: rosa, target: bartz, rng: rng).first).to eq(hp) # replays exactly
  end

  it "revives a fallen ally, and only a fallen one" do
    hp, = described_class.use_item(items["phoenix_down"], user: rosa, target: bartz.merge("hp" => 0), rng: rng)
    expect(hp).to eq(bartz["stats"]["max_hp"] / 4)
    expect { described_class.use_item(items["phoenix_down"], user: rosa, target: bartz, rng: rng) }
      .to raise_error(Battle::InvalidAction, "Bartz isn't down")
  end

  it "refuses what would do nothing, or only works in battle" do
    expect { described_class.use_item(items["potion"], user: rosa, target: bartz.merge("hp" => 0), rng: rng) }
      .to raise_error(Battle::InvalidAction, /is down/)
    expect { described_class.use_item(items["potion"], user: rosa, target: rosa.merge("hp" => 80), rng: rng) }
      .to raise_error(Battle::InvalidAction, "Rosa is already at full HP")
    expect { described_class.use_item(items["remedy"], user: rosa, target: bartz, rng: rng) }
      .to raise_error(Battle::InvalidAction, "Remedy can only be used in battle")
    expect(described_class.usable?(items["antidote"])).to be(false)
  end

  it "lets you use one on yourself" do
    hp, = described_class.use_item(items["potion"], user: bartz, target: bartz, rng: rng)
    expect(hp).to be > 30
  end
end
