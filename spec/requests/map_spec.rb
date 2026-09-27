# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe "Map pages", type: :request do
  let!(:world) { Seeds::BaseWorld.run }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let!(:tule) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true) }
  let!(:ruins) { campaign.map_nodes.create!(name: "Secret Ruins", kind: "dungeon", x: 400, y: 300) }
  let!(:bartz) { campaign.characters.create!(name: "Bartz", job: world.jobs.find_by!(slug: "knight")) }

  def sit(seat)
    post campaign_table_seat_path(campaign), params: { seat: seat }
  end

  it "shows players only what's been revealed" do
    sit(bartz.id)
    get campaign_map_path(campaign)
    expect(response.body).to include("Tule")
    expect(response.body).not_to include("Secret Ruins", "data-map-node", "map_panel")
    get campaign_table_path(campaign)
    expect(response.body).to include("Tule")
    expect(response.body).not_to include("Secret Ruins")
  end

  it "keeps the editing tools to the GM" do
    sit(bartz.id)
    get campaign_map_panel_path(campaign)
    expect(response).to have_http_status(:forbidden)
    post campaign_map_nodes_path(campaign), params: { map_node: { name: "X", kind: "field", x: 1, y: 1 } }
    expect(response).to have_http_status(:forbidden)
    patch map_node_path(tule, format: :json), params: { map_node: { x: 5, y: 5 } }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(tule.reload.x).to eq(100)
  end

  describe "as GM" do
    before { sit("gm") }

    it "shows everything, with hidden places marked, and the editor" do
      get campaign_map_path(campaign)
      expect(response.body).to include("Secret Ruins", "is-hidden", 'data-controller="map-editor"', "map_panel")
    end

    it "adds a place where the map was clicked, then edits and reveals it" do
      get new_campaign_map_node_path(campaign, x: 640, y: 9999)
      expect(response.body).to include('value="640"', 'value="700"') # clamped to the map

      post campaign_map_nodes_path(campaign), params: { map_node: { name: "Walse", kind: "town", x: 640, y: 200, visible: "0" } }
      walse = campaign.map_nodes.find_by!(name: "Walse")
      expect(response).to redirect_to(edit_map_node_path(walse))

      patch map_node_path(walse), params: { map_node: { name: "Walse", kind: "town", visible: "1", notes: "Castle" } }
      expect(walse.reload).to have_attributes(visible: true, notes: "Castle")
    end

    it "moves a place by dragging (JSON)" do
      patch map_node_path(tule, format: :json), params: { map_node: { x: 222, y: 333 } }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(tule.reload).to have_attributes(x: 222, y: 333)
    end

    it "connects places, edits the path and cuts it" do
      post map_node_map_edges_path(tule), params: { map_edge: { to_node_id: ruins.id, state: "dangerous", encounter_table_id: world.encounter_tables.first.id } }
      edge = campaign.map_edges.sole
      expect(response).to redirect_to(edit_map_edge_path(edge))

      patch map_edge_path(edge), params: { map_edge: { state: "blocked", encounter_table_id: "", travel_event: "Rockslide." } }
      expect(edge.reload).to have_attributes(state: "blocked", encounter_table: nil, travel_event: "Rockslide.")

      delete map_edge_path(edge)
      expect(campaign.map_edges).to be_empty
    end

    it "shows the resolver of a failed connection" do
      post map_node_map_edges_path(tule), params: { map_edge: { to_node_id: tule.id, state: "open" } }
      follow_redirect!
      expect(response.body).to include("must be a different place")
    end

    it "places the party, travels, and deals with the encounter" do
      campaign.map_edges.create!(from_node: tule, to_node: ruins, state: "dangerous", encounter_table: world.encounter_tables.find_by!(slug: "grasslands"))
      post place_party_map_node_path(tule)
      get campaign_map_panel_path(campaign)
      expect(response.body).to include("The party is at Tule", "To Secret Ruins", "dangerous · Grasslands")

      post campaign_travel_path(campaign), params: { edge_id: campaign.map_edges.sole.id }
      follow_redirect!
      expect(response.body).to include("The party is at Secret Ruins", "Encounter!", "Fight", "Wave it off")

      expect(response.body).to include("Input timer")
      post campaign_encounter_path(campaign), params: { input_seconds: "30" }
      battle = campaign.battles.last
      expect(response).to redirect_to(battle_path(battle))
      expect(battle.party.map { |u| u["name"] }).to eq([ "Bartz" ])
      expect(battle.input_seconds).to eq(30)
    end

    it "says when a path is safe because it has no encounter table" do
      campaign.map_edges.create!(from_node: tule, to_node: ruins, state: "dangerous")
      campaign.place_party!(tule)
      get campaign_map_panel_path(campaign)
      expect(response.body).to include("dangerous · safe")
    end

    it "reports a blocked path instead of travelling" do
      campaign.map_edges.create!(from_node: tule, to_node: ruins, state: "blocked")
      campaign.place_party!(tule)
      post campaign_travel_path(campaign), params: { edge_id: campaign.map_edges.sole.id }
      follow_redirect!
      expect(response.body).to include("That path is blocked")
    end

    it "removes a place, taking its paths and the party marker with it" do
      campaign.map_edges.create!(from_node: tule, to_node: ruins)
      campaign.place_party!(tule)
      delete map_node_path(tule)
      expect(campaign.reload.current_node).to be_nil
      expect(campaign.map_edges).to be_empty
    end
  end

  describe "Encounter Tables book" do
    it "has CRUD and a page like the other books" do
      post world_encounters_encounter_tables_path(world), params: { encounter_table: {
        name: "Shore", terrain: "sea", tier: "2",
        entries: { "0" => { weight: "1", monster: "flan", count: "2", monster_2: "", count_2: "" } }
      } }
      expect(response).to redirect_to(world_encounters_encounter_table_path(world, "shore"))
      follow_redirect!
      expect(response.body).to include("Shore", "2 × ", "Flan", "100%")

      get world_bestiary_monster_path(world, "flan")
      expect(response.body).to include("Found in", "Shore", "Barrow")
    end
  end
end
