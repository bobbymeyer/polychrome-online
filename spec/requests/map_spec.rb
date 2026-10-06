# frozen_string_literal: true

require "rails_helper"

# Maps (docs/HANDOFF.md §7, "Maps"): several a campaign, each a 16:9 picture with places and child maps on
# it and siblings off its edges; shown on the stage when the GM says; edited on the GM's maps page.
RSpec.describe "Maps", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let(:root) { campaign.root_map }
  let!(:tule) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true) }
  let!(:ruins) { campaign.map_nodes.create!(name: "Secret Ruins", kind: "dungeon", x: 400, y: 300) }
  let!(:bartz) { campaign.characters.create!(name: "Bartz", job: world.jobs.find_by!(slug: "knight")) }

  def sit(seat)
    post campaign_table_seat_path(campaign), params: { seat: seat }
  end

  it "starts every place on the campaign's root map, named for the world, in a 16:9 space" do
    expect(root.name).to eq(world.name)
    expect(tule.map).to eq(root)
    expect(MapNode::WIDTH.to_f / MapNode::HEIGHT).to eq(16.0 / 9)
    expect(campaign.map_nodes.new(name: "Far", x: 1601, y: 10)).not_to be_valid
  end

  it "puts a place's name over it when the name under it is taken" do
    campaign.map_nodes.create!(name: "Varn", kind: "town", x: 600, y: 500, visible: true)
    campaign.map_nodes.create!(name: "Goblin Hollow", kind: "dungeon", x: 630, y: 510, visible: true)
    sit("gm")
    get campaign_maps_path(campaign)
    expect(response.body).to include('<text class="map-node__label" y="38" text-anchor="middle">Varn</text>',
                                     '<text class="map-node__label is-above" y="-24" text-anchor="middle">Goblin Hollow</text>')
  end

  describe "on the stage" do
    it "waits until the GM shows it, then everyone sees the party's map, players without hidden places" do
      sit(bartz.id)
      get campaign_table_path(campaign)
      expect(response.body).to include('id="table_map"', "hidden")
      expect(response.body).not_to include("Secret Ruins", "map-sheet")

      campaign.update!(current_node: tule)
      campaign.show_map!
      get campaign_table_path(campaign)
      expect(response.body).to include("map-sheet", "Tule", 'class="map-party"', %(aria-label="#{world.name}: the party is at Tule"))
      expect(response.body).not_to include("Secret Ruins", "data-map-node")
      expect(Nokogiri::HTML(response.body).at("#table_scene")["hidden"]).not_to be_nil # the place's picture steps aside for the map

      expect(response.body).not_to include("table-time__view") # the switch is the GM's
      sit("gm")
      get campaign_table_path(campaign)
      expect(response.body).to include("Secret Ruins", "is-hidden")
      expect(Nokogiri::HTML(response.body).at("#stage .table-time__where .table-time__view").text).to eq("Place") # on the place's tag: the stage is the switch
      patch campaign_map_view_path(campaign), params: { off: 1 }
      expect(campaign.reload).not_to be_map_on_stage
      get campaign_table_path(campaign)
      expect(Nokogiri::HTML(response.body).at("#stage .table-time__where .table-time__view").text).to eq("Map")
    end

    it "is the GM's to steer, by the maps beside it and the ones on it; a player browses alone" do
      region = campaign.maps.create!(name: "The Western Marches", parent: root, x: 800, y: 450)
      far = campaign.maps.create!(name: "The Frozen North")
      campaign.map_links.create!(from_map: root, to_map: far, direction: "n")
      campaign.update!(current_node: tule)
      campaign.show_map!

      sit("gm")
      get campaign_table_path(campaign)
      page = Nokogiri::HTML(response.body)
      north = page.at("#table_map .map-sheet__edge--n a")
      expect(north.text).to eq("The Frozen North")
      expect(north["data-turbo-method"]).to eq("patch") # the GM's press moves everyone
      child = page.at("#table_map .map-child a")
      expect(child["href"]).to eq(campaign_map_view_path(campaign, map: region.id))
      expect(page.at("#table_map .map-child text").text).to eq("The Western Marches")

      patch campaign_map_view_path(campaign), params: { map: far.id }
      expect(campaign.reload.map_shown).to eq(far)
      get campaign_table_path(campaign)
      page = Nokogiri::HTML(response.body)
      expect(page.at("#table_map .map-sheet__name").text).to eq("The Frozen North")
      expect(page.at("#table_map .map-sheet__edge--s a").text).to eq(world.name) # read the other way round
      expect(page.at("#table_map .map-party")).to be_nil # the party isn't on this one

      sit(bartz.id)
      get campaign_map_view_path(campaign, map: region.id) # browsing: this viewer's frame alone
      page = Nokogiri::HTML(response.body)
      expect(page.at("turbo-frame#table_map .map-sheet__name").text).to eq("The Western Marches")
      expect(page.at("turbo-frame#table_map .map-sheet__up").text).to eq("↑ #{world.name}")
      expect(page.at(".map-sheet__up")["data-turbo-frame"]).to eq("table_map")
      expect(campaign.reload.map_shown).to eq(far) # nobody else moved
      patch campaign_map_view_path(campaign), params: { map: region.id }
      expect(response).to have_http_status(:see_other) # the GM seat's
    end

    it "splits an edge between the maps that share it, and draws a road through its bends" do
      a = campaign.maps.create!(name: "Eastmarch")
      b = campaign.maps.create!(name: "Eastholm")
      campaign.map_links.create!(from_map: root, to_map: a, direction: "e")
      campaign.map_links.create!(from_map: b, to_map: root, direction: "w") # root is west of b: b is east of root
      road = campaign.map_edges.create!(from_node: tule, to_node: ruins, waypoints: [ [ 200, 250 ], [ 300, 200 ] ])
      ruins.update!(visible: true)
      campaign.show_map!
      sit(bartz.id)
      get campaign_table_path(campaign)
      page = Nokogiri::HTML(response.body)
      expect(page.css("#table_map .map-sheet__edge--e a").map(&:text)).to eq(%w[Eastmarch Eastholm])
      expect(page.at("#table_map .map-edge__line")["d"]).to start_with("M100 100 C").and include("300 200", "400 300")
      expect(road.points).to eq([ [ 100, 100 ], [ 200, 250 ], [ 300, 200 ], [ 400, 300 ] ])
    end

    it "shows the picture under the places when the map has one" do
      root.image.attach(io: StringIO.new(FakeComfy.png), filename: "world.png", content_type: "image/png")
      campaign.show_map!
      sit(bartz.id)
      get campaign_table_path(campaign)
      expect(response.body).to include("map-sheet--pictured", 'class="map__picture"', 'preserveAspectRatio="xMidYMid slice"')
    end
  end

  describe "the GM's maps page" do
    it "is the GM's alone, with the editor, every map, and hidden places marked" do
      sit(bartz.id)
      get campaign_maps_path(campaign)
      expect(response).to have_http_status(:see_other) # the GM seat's: turned back with a word

      sit("gm")
      get campaign_maps_path(campaign)
      expect(response.body).to include("Secret Ruins", "is-hidden", 'data-controller="map-editor"', "map_panel", "map-sheet--editor",
                                       "New map on #{world.name}", "Generate the picture", "Put it on the stage")
    end

    it "makes a map on another, moves it by dragging, puts it beside one, and takes it away" do
      sit("gm")
      post campaign_maps_path(campaign), params: { parent_id: root.id, map: { name: "The Western Marches" } }
      region = campaign.maps.find_by!(name: "The Western Marches")
      expect(region.parent).to eq(root)
      expect(response).to redirect_to(campaign_maps_path(campaign, map: region.id))

      patch campaign_map_path(campaign, region, format: :json), params: { map: { x: 1200, y: 600 } }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(region.reload).to have_attributes(x: 1200, y: 600)
      get campaign_maps_path(campaign, map: root.id)
      expect(response.body).to include('class="map-child" transform="translate(1200 600)"', "data-map-child")

      post campaign_map_map_links_path(campaign, region), params: { map_link: { to_map_id: root.id, direction: "n" } }
      expect(flash[:notice]).to eq("#{world.name} is north of The Western Marches.")
      expect(root.neighbours["s"]).to eq([ region ])
      post campaign_map_map_links_path(campaign, root), params: { map_link: { to_map_id: region.id, direction: "e" } }
      expect(flash[:alert]).to eq("Those two maps are already side by side")

      patch campaign_map_path(campaign, region), params: { map: { name: "The Marches", parent_id: "", description: "Wet." } }
      expect(region.reload).to have_attributes(name: "The Marches", parent: nil, description: "Wet.")
      patch map_node_path(ruins), params: { map_node: { name: "Secret Ruins", kind: "dungeon", map_id: region.id } }
      expect(ruins.reload.map).to eq(region)

      delete campaign_map_path(campaign, region)
      expect(Map.exists?(region.id)).to be(false)
      expect(ruins.reload.map).to be_nil # on no map until put somewhere
      delete campaign_map_path(campaign, root)
      expect(flash[:alert]).to eq("The campaign needs one map at least")
    end

    it "adds a place where the map was clicked, on that map, and moves it by dragging" do
      sit("gm")
      region = campaign.maps.create!(name: "The Marches")
      get new_campaign_map_node_path(campaign, map_id: region.id, x: 640, y: 9999)
      expect(response.body).to include('value="640"', 'value="900"') # clamped to the map
      post campaign_map_nodes_path(campaign), params: { map_node: { name: "Walse", kind: "town", x: 640, y: 200, visible: "0", map_id: region.id } }
      walse = campaign.map_nodes.find_by!(name: "Walse")
      expect(walse.map).to eq(region)
      patch map_node_path(walse, format: :json), params: { map_node: { x: 222, y: 333 } }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(walse.reload).to have_attributes(x: 222, y: 333)
    end

    it "bends a road where it was clicked, moves the bend, and takes it out" do
      sit("gm")
      road = campaign.map_edges.create!(from_node: tule, to_node: ruins)
      patch map_edge_path(road, format: :json), params: { bend: { x: 250, y: 150 } }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(road.reload.waypoints).to eq([ [ 250, 150 ] ])
      patch map_edge_path(road, format: :json), params: { bend: { x: 120, y: 110 } }, as: :json # nearer the start: first
      expect(road.reload.waypoints).to eq([ [ 120, 110 ], [ 250, 150 ] ])
      patch map_edge_path(road, format: :json), params: { map_edge: { waypoints: [ [ 130, 120 ] ] } }, as: :json
      expect(road.reload.waypoints).to eq([ [ 130, 120 ] ])
      expect(road.points).to eq([ [ 100, 100 ], [ 130, 120 ], [ 400, 300 ] ])
      sit(bartz.id)
      patch map_edge_path(road, format: :json), params: { bend: { x: 1, y: 1 } }, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "keeps the editing to the GM" do
      sit(bartz.id)
      get campaign_map_panel_path(campaign)
      expect(response).to have_http_status(:see_other)
      post campaign_map_nodes_path(campaign), params: { map_node: { name: "X", kind: "field", x: 1, y: 1 } }
      expect(response).to have_http_status(:see_other)
      patch map_node_path(tule, format: :json), params: { map_node: { x: 5, y: 5 } }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(tule.reload.x).to eq(100)
      post campaign_maps_path(campaign), params: { map: { name: "Mine" } }
      expect(campaign.maps.count).to eq(1)
    end

    it "edits a place in the panel, and as a page of its own when opened directly" do
      sit("gm")
      get edit_map_node_path(ruins), headers: { "Turbo-Frame" => "map_panel" }
      expect(response.body).to include('id="map_panel"', "Secret Ruins")
      expect(response.body).not_to include("topbar") # just the panel, for the maps page

      get edit_map_node_path(ruins)
      expect(response.body).to include("topbar", "stylesheet", 'id="map_panel"', "Secret Ruins") # a whole, styled page
    end

    it "connects places, edits the path and cuts it" do
      sit("gm")
      post map_node_map_edges_path(tule), params: { map_edge: { to_node_id: ruins.id, state: "dangerous", encounter_table_id: world.encounter_tables.first.id } }
      edge = campaign.map_edges.last
      expect(edge).to have_attributes(from_node: tule, to_node: ruins, state: "dangerous")
      expect(response).to redirect_to(edit_map_edge_path(edge))

      patch map_edge_path(edge), params: { map_edge: { state: "blocked" } }
      expect(edge.reload.state).to eq("blocked")
      delete map_edge_path(edge)
      expect(MapEdge.exists?(edge.id)).to be(false)
    end
  end

  describe "the stage's map" do
    it "is a map of its own that can't be its own parent, nor under its own child" do
      region = campaign.maps.create!(name: "A", parent: root)
      expect(region.update(parent: region)).to be(false)
      region.reload
      expect(root.update(parent: region)).to be(false)
      expect(root.errors[:parent]).to include("can't be one of this map's own children")
      expect(region.whereabouts).to eq("On #{world.name}")
    end
  end
end
