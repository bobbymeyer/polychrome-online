# frozen_string_literal: true

require "rails_helper"

RSpec.describe Monster::Trial do
  let(:world) { base_world }
  let(:goblin) { world.monsters.find_by!(slug: "goblin") }

  def hp(trial) = trial.party.first[:stats]["max_hp"]

  describe ".level_for" do
    it "is the reference level for anything at or below it, and a creature's own level above" do
      expect(described_class.level_for(Monster.new(level: 1))).to eq(5)
      expect(described_class.level_for(Monster.new(level: 5))).to eq(5)
      expect(described_class.level_for(Monster.new(level: 40))).to eq(40)
      expect(described_class.level_for(Monster.new(level: 500))).to eq(Stats::Growth::MAX_LEVEL)
    end
  end

  it "tries a creature of the reference level or below against the same level-5 party it always has" do
    goblin.update!(level: 2)
    trial = described_class.new(goblin)
    expect(trial.level).to eq(5)
    # Stats::Growth at level 5 is the fixed adventurer the trial used to be built on: 150 HP, 30 MP, 12 in the core stats.
    expect(Stats::Growth.base_stats(5)).to include("max_hp" => 150, "max_mp" => 30, "str" => 12, "mag" => 12, "vit" => 12, "spr" => 12, "agi" => 12)
  end

  it "tries a creature labelled above it against a party of its own level, with the same gear" do
    goblin.update!(level: 40)
    own = described_class.new(goblin)
    reference = described_class.new(goblin, level: 5)
    expect(own.level).to eq(40)
    expect(reference.level).to eq(5)
    expect(hp(own)).to be > hp(reference) * 3
    expect(own.party.map { |u| u[:name] }).to eq(reference.party.map { |u| u[:name] })
  end

  it "takes a level asked for, within the game's levels" do
    expect(described_class.new(goblin, level: 12).level).to eq(12)
    expect(described_class.new(goblin, level: 0).level).to eq(1)
    expect(described_class.new(goblin, level: 1000).level).to eq(Stats::Growth::MAX_LEVEL)
  end
end
