# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A setting's canon: atlas, cast and codex", type: :request do
  let!(:world) { base_world_without_atlas } # draws its own map
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let!(:varn) { world.world_places.create!(name: "Varn", kind: "town", x: 200, y: 200, known: true, location_template: village, description: "Rain, rust and ropes.", notes: "The Syndicate owns the docks.") }
  let!(:lighthouse) { world.world_places.create!(name: "The Old Light", kind: "landmark", x: 500, y: 150, description: "It still turns, with no keeper.") }
  let!(:road) { world.world_routes.create!(from_place: varn, to_place: lighthouse, state: "dangerous", encounter_table: world.encounter_tables.first, travel_event: "Gulls, then silence.") }
  let!(:mara) do
    world.world_figures.create!(name: "Mara Vell", title: "Boss of the Brass Syndicate", blurb: "Never raises her voice.",
                                description: "She sold the lighthouse keeper out.", world_place: varn, monster: world.monsters.find_by!(slug: "goblin"))
  end

  it "starts a new campaign with the atlas on its map and the cast as its NPCs, the same every time" do
    post world_campaigns_path(world), params: { campaign: { name: "Rust" } }
    campaign = world.campaigns.find_by!(name: "Rust")
    nodes = campaign.map_nodes.order(:name)
    expect(nodes.map { |n| [ n.name, n.kind, n.visible, n.description ] }).to eq([
      [ "The Old Light", "landmark", false, "It still turns, with no keeper." ],
      [ "Varn", "town", true, "Rain, rust and ropes." ]
    ])
    town = nodes.last.location
    expect(town).to have_attributes(location_template: village, seed: varn.seed, name: "Varn")
    expect(campaign.map_edges.sole).to have_attributes(state: "dangerous", travel_event: "Gulls, then silence.", world_route: road)
    npc = campaign.npcs.sole
    expect(npc).to have_attributes(name: "Mara Vell", title: "Boss of the Brass Syndicate", location: town, world_figure: mara)
    expect(npc).to be_antagonist

    other = world.campaigns.create!(name: "Again", gm: @admin)
    Atlas.new(other).bring_in_all!
    expect(other.locations.sole.view).to eq(town.view) # the same Varn
  end

  it "can start from nothing, and brings in later what the world has gained, never twice" do
    post world_campaigns_path(world), params: { campaign: { name: "Blank" }, blank_map: "1" }
    campaign = world.campaigns.find_by!(name: "Blank")
    expect(campaign.map_nodes).to be_empty

    get campaign_path(campaign)
    expect(response.body).to include("New in #{world.name}", "Varn", "Mara Vell")
    post campaign_canon_path(campaign)
    expect(campaign.map_nodes.count).to eq(2)
    expect(campaign.npcs.count).to eq(1)

    world.world_places.create!(name: "Saltmarsh", kind: "wilds", x: 700, y: 400)
    post campaign_canon_path(campaign)
    expect(flash[:notice]).to eq("From #{world.name}: 1 place on the map.")
    expect(campaign.map_nodes.count).to eq(3)
    post campaign_canon_path(campaign)
    expect(flash[:notice]).to eq("Nothing new from #{world.name}.")
  end

  it "starts a campaign with the setting's maps: their pictures, parents, neighbours, and the places and bent roads on them" do
    root = world.root_map
    marches = world.world_maps.create!(name: "The Marches", parent: root, x: 1000, y: 500, description: "Wet.")
    north = world.world_maps.create!(name: "The North")
    world.world_map_links.create!(from_map: root, to_map: north, direction: "n")
    marches.image.attach(io: StringIO.new(FakeComfy.png), filename: "marches.png", content_type: "image/png")
    lighthouse.update!(world_map: marches)
    road.update!(waypoints: [ [ 300, 200 ] ])

    post world_campaigns_path(world), params: { campaign: { name: "Rust" } }
    campaign = world.campaigns.find_by!(name: "Rust")
    copies = campaign.maps.in_order
    expect(copies.map { |m| [ m.name, m.parent&.name, m.x, m.y, m.description, m.image.attached? ] }).to eq([
      [ world.name, nil, nil, nil, nil, false ], [ "The Marches", world.name, 1000, 500, "Wet.", true ], [ "The North", nil, nil, nil, nil, false ]
    ])
    expect(copies.first.neighbours["n"].map(&:name)).to eq([ "The North" ])
    expect(copies.map(&:world_map)).to eq([ root, marches, north ])
    expect(campaign.map_nodes.find_by!(name: "The Old Light").map.name).to eq("The Marches")
    expect(campaign.map_nodes.find_by!(name: "Varn").map).to eq(copies.first)
    expect(campaign.map_edges.sole.waypoints).to eq([ [ 300, 200 ] ])

    # Brought in again later: nothing twice.
    Atlas.new(campaign).bring_in_all!
    expect(campaign.maps.count).to eq(3)
    expect(campaign.map_links.count).to eq(1)

    # A world copied from this one keeps the maps too.
    other = World.create!(name: "Other", slug: "other-maps")
    other.copy_books_from!(world)
    expect(other.world_maps.in_order.map { |m| [ m.name, m.parent&.name ] }).to eq([ [ world.name, nil ], [ "The Marches", world.name ], [ "The North", nil ] ])
    expect(other.world_maps.find_by!(name: "The Marches").image).to be_attached
    expect(other.world_places.find_by!(name: "The Old Light").world_map.name).to eq("The Marches")
    expect(other.world_map_links.sole.direction).to eq("n")
  end

  it "shows players a place's description on the map" do
    campaign = world.campaigns.create!(name: "Rust", gm: @admin)
    Atlas.new(campaign).bring_in_all!
    campaign.place_party!(campaign.map_nodes.find_by!(name: "Varn"))
    campaign.show_map!
    sign_in_as(make_user("Player"))
    get campaign_table_path(campaign)
    expect(response.body).to include("<desc>Rain, rust and ropes.</desc>")
  end

  it "keeps the atlas and cast to the world's editors and GMs, and the codex's GM side from players" do
    world.codex_entries.create!(title: "The Brass Syndicate", category: "Faction", body: "They own the docks.", gm_notes: "Mara's ledger is fake.")
    world.codex_entries.create!(title: "The Drowned Saint", body: "Nobody prays to her.", public: false)

    get world_world_places_path(world)
    expect(response.body).to include("Varn", "The Syndicate owns the docks.", "The Old Light")
    get world_world_figures_path(world)
    expect(response.body).to include("Mara Vell", "Never raises her voice.")
    get world_codex_entry_path(world, world.codex_entries.find_by!(title: "The Brass Syndicate"))
    expect(response.body).to include("They own the docks.", "Mara's ledger is fake.")

    sign_in_as(make_user("Player"))
    get world_world_places_path(world)
    expect(response).to have_http_status(:see_other) # turned away
    get world_codex_entries_path(world)
    expect(response.body).to include("The Brass Syndicate")
    expect(response.body).not_to include("The Drowned Saint")
    get world_codex_entry_path(world, world.codex_entries.find_by!(title: "The Brass Syndicate"))
    expect(response.body).not_to include("ledger is fake")
    get world_codex_entry_path(world, world.codex_entries.find_by!(title: "The Drowned Saint"))
    expect(response).to have_http_status(:see_other)
  end

  it "writes the atlas, roads, cast and codex through their forms" do
    post world_world_places_path(world), params: { world_place: { name: "Saltmarsh", kind: "wilds", x: 700, y: 400, known: "0", description: "Reeds.", location_template_id: "" } }
    expect(world.world_places.find_by!(name: "Saltmarsh")).to have_attributes(kind: "wilds", seed: nil)
    post world_world_places_path(world), params: { world_place: { name: "Bad", kind: "dungeon", x: 1, y: 1, location_template_id: village.id } }
    expect(response.body).to include("is a town, and this is a dungeon")
    post world_world_routes_path(world), params: { world_route: { from_place_id: varn.id, to_place_id: varn.id, state: "open" } }
    expect(flash[:alert]).to include("must be another place")
    post world_world_figures_path(world), params: { world_figure: { name: "Pell", title: "Keeper" } }
    expect(world.world_figures.find_by!(name: "Pell").title).to eq("Keeper")
    post world_codex_entries_path(world), params: { codex_entry: { title: "Tides", category: "Custom", body: "Twice a day.", public: "1" } }
    expect(response).to redirect_to(world_codex_entry_path(world, world.codex_entries.find_by!(title: "Tides")))
  end

  it "goes with the books when the world is copied" do
    world.codex_entries.create!(title: "Tides", body: "Twice a day.")
    copy = World.create!(name: "Copy", slug: "copy", owner: @admin)
    copy.copy_books_from!(world)
    expect(copy.world_places.find_by!(name: "Varn")).to have_attributes(seed: varn.seed, location_template: copy.location_templates.find_by!(slug: "village"))
    expect(copy.world_routes.sole.from_place.world).to eq(copy)
    expect(copy.world_figures.sole).to have_attributes(monster: copy.monsters.find_by!(slug: "goblin"), world_place: copy.world_places.find_by!(name: "Varn"))
    expect(copy.codex_entries.sole.title).to eq("Tides")
  end

  it "tells the language model the setting's lore" do
    world.codex_entries.create!(title: "The Brass Syndicate", category: "Faction", body: "They own the docks.")
    draft = Draft.new(owner: world, kind: "setting", request: {})
    expect(draft.writer.messages[:user]).to include("The Brass Syndicate (Faction): They own the docks.", "Places in the setting: The Old Light, Varn.", "Mara Vell, Boss of the Brass Syndicate")
  end
end
