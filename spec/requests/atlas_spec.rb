# frozen_string_literal: true

require "rails_helper"

# A setting's maps (WorldMap), edited on the atlas by the world's editors: the same sheet as a campaign's.
RSpec.describe "The atlas's maps", type: :request do
  let!(:world) { base_world_without_atlas }
  let(:root) { world.root_map }
  let!(:varn) { world.world_places.create!(name: "Varn", kind: "town", x: 200, y: 200, known: true) }
  let!(:light) { world.world_places.create!(name: "The Old Light", kind: "landmark", x: 500, y: 150) }
  let!(:road) { world.world_routes.create!(from_place: varn, to_place: light) }

  it "starts with one map named for the world, every place on it" do
    expect(root.name).to eq(world.name)
    expect(varn.world_map).to eq(root)
    get world_world_places_path(world)
    expect(response.body).to include("map-sheet--editor", 'data-controller="map-editor"', "New map on #{world.name}", "Generate the picture", "Varn", "The Old Light")
  end

  it "makes maps on maps and beside them, moves them and the places, bends the roads, and keeps it to editors" do
    post world_world_maps_path(world), params: { parent_id: root.id, world_map: { name: "The Marches", description: "Wet." } }
    marches = world.world_maps.find_by!(name: "The Marches")
    expect(marches.parent).to eq(root)
    expect(response).to redirect_to(world_world_places_path(world, map: marches.id))

    patch world_world_map_path(world, marches, format: :json), params: { world_map: { x: 900, y: 400 } }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(marches.reload).to have_attributes(x: 900, y: 400)

    post world_world_map_world_map_links_path(world, root), params: { world_map_link: { to_map_id: marches.id, direction: "w" } }
    expect(flash[:notice]).to eq("The Marches is west of #{world.name}.")
    expect(marches.reload.neighbours["e"]).to eq([ root ])

    get new_world_world_place_path(world, world_map_id: marches.id, x: 700, y: 9999)
    expect(response.body).to include('value="700"', 'value="900"', %(<option selected="selected" value="#{marches.id}">The Marches</option>))
    post world_world_places_path(world), params: { world_place: { name: "Fen", kind: "wilds", x: 700, y: 800, world_map_id: marches.id, known: "1" } }
    fen = world.world_places.find_by!(name: "Fen")
    expect(fen.world_map).to eq(marches)
    patch world_world_place_path(world, fen, format: :json), params: { world_place: { x: 710, y: 810 } }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(fen.reload).to have_attributes(x: 710, y: 810)

    patch world_world_route_path(world, road, format: :json), params: { bend: { x: 350, y: 120 } }, as: :json
    expect(road.reload.waypoints).to eq([ [ 350, 120 ] ])
    get edit_world_world_route_path(world, road)
    expect(response.body).to include("Bent through 1 point")
    patch world_world_route_path(world, road), params: { world_route: { state: "dangerous", duration: 2 } }
    expect(road.reload).to have_attributes(state: "dangerous", duration: 2, waypoints: [ [ 350, 120 ] ])

    get world_world_places_path(world, map: marches.id)
    page = Nokogiri::HTML(response.body)
    expect(page.at(".map-sheet__up").text).to eq("↑ #{world.name}")
    expect(page.at(".map-sheet__edge--e a").text).to eq(world.name)
    expect(page.css(".map-node text.map-node__label").map(&:text)).to eq([ "Fen" ])

    delete world_world_map_path(world, marches)
    expect(WorldMap.exists?(marches.id)).to be(false)
    expect(fen.reload.world_map).to be_nil
    delete world_world_map_path(world, root)
    expect(flash[:alert]).to eq("The atlas needs one map at least.")

    sign_in_as(make_user("Reader"))
    post world_world_maps_path(world), params: { world_map: { name: "Mine" } }
    expect(world.world_maps.count).to eq(1)
    patch world_world_place_path(world, varn, format: :json), params: { world_place: { x: 1 } }, as: :json
    expect(varn.reload.x).to eq(200)
  end
end
