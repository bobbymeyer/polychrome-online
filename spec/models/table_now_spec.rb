# frozen_string_literal: true

require "rails_helper"

# What the table's Now line says (campaigns/tables/_now): the state the
# table is in, the clocks about to fill, and who waits on the road.
RSpec.describe "The table, right now" do
  let(:campaign) { create_campaign }

  it "is in the first state that holds: a battle, then an encounter, then a choice, then free play" do
    create_character(campaign, name: "Bartz")
    expect(campaign.table_state).to eq("free")

    Message.choice(campaign, options: %w[Left Right]).save!
    expect(campaign.reload.table_state).to eq("choice")

    campaign.update!(pending_encounter: { "monsters" => { "goblin" => 2 }, "antagonists" => [ campaign.npcs.create!(name: "Garland").id ] })
    expect(campaign.table_state).to eq("encounter")
    expect(campaign.encounter_foes).to eq([ "Garland", "2 × Goblin" ])

    start_battle(campaign: campaign)
    expect(campaign.reload.table_state).to eq("battle")
  end

  it "knows the clocks one box from full" do
    nearly = campaign.clocks.create!(name: "The docks fall", segments: 4, filled: 3)
    campaign.clocks.create!(name: "The tide comes in", segments: 4, filled: 1)
    expect(campaign.clocks.running.nearly_full).to eq([ nearly ])
  end
end
