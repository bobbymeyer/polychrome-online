# frozen_string_literal: true

require "rails_helper"

# Players steer: "Where next?" as a vote the GM settles, or the GM just going.
RSpec.describe "Where next", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road", gm: @admin) }
  let(:kim) { make_user("Kim") }
  let!(:rook) { create_character(campaign, name: "Rook", user: kim) }
  let(:tule) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 0, y: 0, visible: true) }
  let(:mere) { campaign.map_nodes.create!(name: "Greymere", kind: "wilds", x: 100, y: 0, visible: true) }
  let(:port) { campaign.map_nodes.create!(name: "Port", kind: "town", x: 0, y: 100, visible: true) }
  let(:pass) { campaign.map_nodes.create!(name: "The Pass", kind: "landmark", x: 200, y: 200, visible: true) }

  before do
    campaign.map_edges.create!(from_node: tule, to_node: mere, state: "open")
    campaign.map_edges.create!(from_node: tule, to_node: port, state: "open")
    campaign.map_edges.create!(from_node: tule, to_node: pass, state: "blocked")
    campaign.update!(current_node: tule)
  end

  it "lets a player suggest a way: it goes to a vote, and settling it takes the party there" do
    sign_in_as(kim)
    get campaign_table_path(campaign)
    expect(response.body).to include("Where next?", "To Greymere", "To Port", "suggest")
    expect(response.body).not_to include("To The Pass") # blocked

    post campaign_ways_path(campaign), params: { way: "To Greymere" }
    vote = campaign.open_choice
    expect(vote).to be_where_next
    expect(vote.options).to eq([ "To Greymere", "To Port", Campaign::STAY ])
    expect(vote.tally["To Greymere"]).to eq([ "Rook" ])

    sign_out
    sign_in_as(@admin)
    post choice_settlement_path(vote), params: { option: "To Greymere" }
    expect(campaign.reload.current_node).to eq(mere)
    expect(campaign.messages.pluck(:body)).to include("The party chose: To Greymere.", "The party travels from Tule to Greymere.")
  end

  it "stays put when the party chooses to" do
    vote = campaign.ask_where_next!
    vote.settle!(Campaign::STAY)
    expect(campaign.reload.current_node).to eq(tule)
  end

  it "lets the GM just go, and takes a vote the party moved on from off the table" do
    vote = campaign.ask_where_next!
    post campaign_ways_path(campaign), params: { way: "To Port", go: 1 }
    expect(campaign.reload.current_node).to eq(port)
    expect(Message.exists?(vote.id)).to be(false)
    expect(campaign.open_choice).to be_nil
  end

  it "won't open a vote over another choice, or where there's nowhere to go" do
    Message.choice(campaign, options: %w[Yes No]).save!
    expect { campaign.ask_where_next! }.to raise_error(Refusal, /something else first/)
    campaign.open_choice.settle!("Yes")
    campaign.map_edges.update_all(state: "blocked")
    expect { campaign.ask_where_next! }.to raise_error(Refusal, /nowhere to go/)
  end

  it "offers a dungeon's door, then its ways on, naming only rooms the players have seen" do
    cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
    post map_node_location_path(cave_node), params: { location_template_id: world.location_templates.find_by!(slug: "goblin_cave").id }
    cave = cave_node.reload.location
    campaign.update!(current_node: cave_node)
    expect(campaign.ways_on.first).to eq("label" => "Into #{cave.name}", "move" => { "location" => cave.id, "enter" => true })

    vote = campaign.ask_where_next!
    vote.settle!("Into #{cave.name}")
    expect(cave.reload.progress["current"]).to eq(cave.view["entrance"])
    ways = campaign.reload.ways_on
    expect(ways).to all(include("move" => include("location" => cave.id, "room" => be_present)))
    ways.each do |way|
      seen = cave.seen_by_players?(way.dig("move", "room"))
      expect(way["label"]).to(seen ? start_with(cave.room(way.dig("move", "room"))["name"]) : start_with("An unexplored way"))
    end
  end
end
