# frozen_string_literal: true

require "rails_helper"

RSpec.describe BattleSimulation do
  let(:campaign) { base_campaign }
  let!(:cloud) { base_character(campaign, name: "Cloud", job: "knight", starting_level: 3) }

  it "builds each fight once and gives every run its own seed, the same as building each from scratch" do
    sim = described_class.new(campaign, encounter: { "wolf" => 2 }, runs: 3)
    party = [ cloud.battle_spec.except("hp", "mp") ]
    expect(sim.send(:states)).to eq((1..3).map { |seed| campaign.world.battle(seed: seed, party: party, monsters: { "wolf" => 2 }) })
  end

  it "starts the party rested, or as they are now" do
    cloud.update!(hp: 5)
    rested = described_class.new(campaign, encounter: { "wolf" => 1 }, runs: 1).send(:states).first
    tired = described_class.new(campaign, encounter: { "wolf" => 1 }, runs: 1, rested: false).send(:states).first
    unit = ->(state) { state["units"].find { |u| u["side"] == "party" } }
    expect(unit.(rested)["hp"]).to eq(unit.(rested)["stats"]["max_hp"])
    expect(unit.(tired)["hp"]).to eq(5)
  end

  it "keeps to the world's monsters, a sensible number of runs, and tactics it knows" do
    sim = described_class.new(campaign, encounter: { "wolf" => "20", "nothing_like_it" => 2, "goblin" => 0 }, runs: 5000, tactics: "clever")
    expect(sim.encounter).to eq("wolf" => 8)
    expect(sim).to have_attributes(runs: described_class::MAX_RUNS, tactics: "full")
    expect(described_class.new(campaign, runs: 1)).not_to be_ready
    expect(described_class.new(campaign, runs: 1).result).to be_nil
  end
end
