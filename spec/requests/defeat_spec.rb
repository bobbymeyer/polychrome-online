# frozen_string_literal: true

require "rails_helper"

# After a wipe, the GM decides what the story does with the party.
RSpec.describe "Defeat", type: :request do
  let(:campaign) { create_campaign.tap { |c| c.update!(gm: @admin, gil: 301) } }
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let!(:faris) { create_character(campaign, name: "Faris") }
  let(:tule) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 0, y: 0, visible: true) }
  let(:far_town) { campaign.map_nodes.create!(name: "Walse", kind: "town", x: 900, y: 0, visible: true) }
  let(:ruins) { campaign.map_nodes.create!(name: "Ruins", kind: "dungeon", x: 300, y: 0, visible: true) }

  before do
    far_town
    campaign.map_edges.create!(from_node: tule, to_node: ruins)
    campaign.update!(current_node: ruins)
    [ bartz, faris ].each { |c| c.update!(hp: 0) }
  end

  it "offers the GM a way on at the table and on the battle's results" do
    get campaign_table_path(campaign)
    expect(response.body).to include("Everyone is down. What happens now?", "Retreat to Tule", "Everyone gets up", "Game over")

    battle = start_battle(campaign: campaign)
    battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "defeat" }, actor: "gm")
    get battle_panel_path(battle)
    expect(response.body).to include("Retreat to Tule")
  end

  it "retreats to the nearest town by road, rested and half as rich" do
    post campaign_recovery_path(campaign), params: { how: "retreat" }
    campaign.reload
    expect(campaign.current_node).to eq(tule)
    expect(campaign.gil).to eq(151)
    expect([ bartz.reload, faris.reload ]).to all(be_conscious)
    expect(bartz.current_hp).to eq(bartz.stats["max_hp"])
    expect(campaign.messages.pluck(:body)).to include("The party comes to in Tule, bruised but alive, 150 gil lighter.")
  end

  it "gets everyone up where they fell, with 1 HP" do
    post campaign_recovery_path(campaign), params: { how: "get_up" }
    expect([ bartz.reload.hp, faris.reload.hp ]).to eq([ 1, 1 ])
    expect(campaign.reload.current_node).to eq(ruins)
  end

  it "can end the story, and only when everyone is down" do
    post campaign_recovery_path(campaign), params: { how: "game_over" }
    expect(campaign.messages.last.body).to eq("The party has fallen. Their story ends here.")
    expect(bartz.reload).not_to be_conscious

    bartz.update!(hp: 5)
    post campaign_recovery_path(campaign), params: { how: "get_up" }
    expect(flash[:alert]).to eq("Someone is still standing")
    expect(faris.reload.hp).to eq(0)
  end

  it "is the GM's call" do
    sign_in_as(make_user("Kim"))
    post campaign_recovery_path(campaign), params: { how: "get_up" }
    expect(bartz.reload.hp).to eq(0)
  end
end
