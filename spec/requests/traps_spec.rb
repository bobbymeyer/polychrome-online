# frozen_string_literal: true

require "rails_helper"

# The GM's hand on a trap in a room (Locations::TrapsController).
RSpec.describe "Traps in a dungeon", type: :request do
  let(:campaign) { base_campaign(gm: @admin) }
  let(:cave) { base_world.location_templates.find_by!(slug: "goblin_cave") }
  let(:dungeon) do
    campaign.locations.create!(location_template: cave, seed: 11).tap do |d|
      campaign.update!(current_node: campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 1, y: 1, location: d))
    end
  end
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let!(:room) do
    dungeon.enter!
    dungeon.add_room!(name: "Gallery", connect: dungeon.view["entrance"], decision: { "kind" => "trap", "text" => "A pit. (hurt 10)" }).tap { |key| dungeon.move_to!(key) }
  end

  it "shows the GM the trap, and lets it go off" do
    sit(campaign, "gm")
    get location_path(dungeon)
    expect(page.at_css(".trap-form")).to be_present
    post location_traps_path(dungeon), params: { room: room, verdict: "spring" }
    expect(dungeon.reload.resolved?(room)).to be(true)
  end

  it "has someone try to disarm it" do
    sit(campaign, "gm")
    post location_traps_path(dungeon), params: { room: room, verdict: "disarm", character_id: bartz.id, stat: "agi", difficulty: "easy" }
    expect(dungeon.reload.resolved?(room)).to be(true)
    expect(campaign.messages.pluck(:body).join).to include("disarm")
  end
end
