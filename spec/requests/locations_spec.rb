# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe "Locations", type: :request do
  let!(:world) { Seeds::BaseWorld.run }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let!(:bartz) { campaign.characters.create!(name: "Bartz", job: world.jobs.find_by!(slug: "knight")) }
  let(:node) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100) }

  def sit(seat)
    post campaign_table_seat_path(campaign), params: { seat: seat }
  end

  def generate(template_slug, on: node)
    sit("gm")
    post map_node_location_path(on), params: { location_template_id: world.location_templates.find_by!(slug: template_slug).id }
    on.reload.location
  end

  it "rolls a location for a map place, named after it" do
    town = generate("village")
    expect(response).to redirect_to(location_path(town))
    expect(town.name).to eq("Tule")
    get location_path(town)
    expect(response.body).to include("Tule", "skyline", "Services", "People", "Reroll")
  end

  it "hides a location from players until its place is revealed, and hides GM secrets" do
    town = generate("village")
    sit(bartz.id)
    get location_path(town)
    expect(response).to have_http_status(:not_found)

    node.update!(visible: true)
    get location_path(town)
    expect(response).to have_http_status(:ok)
    hooks = town.view["npcs"].map { |n| n["hook"] }
    expect(response.body).not_to include(*hooks.map { |h| ERB::Util.html_escape(h) })
    expect(response.body).not_to include("Reroll", "seed")
  end

  it "keeps the GM controls to the GM" do
    town = generate("village")
    sit(bartz.id)
    post reroll_location_path(town)
    expect(response).to have_http_status(:forbidden)
    post pin_location_path(town), params: { key: "npc-0" }
    expect(response).to have_http_status(:forbidden)
  end

  describe "as GM" do
    it "rerolls, pins and makes townsfolk real NPCs" do
      town = generate("village")
      first = town.view["npcs"].first
      post pin_location_path(town), params: { key: first["key"] }
      expect(campaign.npcs.find_by!(location_key: first["key"]).name).to eq(first["name"])

      post reroll_location_path(town)
      follow_redirect!
      expect(response.body).to include("Rerolled", first["name"])

      post add_npc_location_path(town), params: { npc: { name: "Galuf", title: "Old man", description: "Can't remember" } }
      get location_path(town)
      expect(response.body).to include("Galuf", "Can&#39;t remember")
    end

    it "sets and resets the stock, and renames" do
      town = generate("village")
      patch stock_location_path(town), params: { stock: { items: [ "", "phoenix_down" ] } }
      expect(town.reload.view["stock"]).to eq([ "phoenix_down" ])
      patch stock_location_path(town), params: { reset: 1 }
      expect(town.reload.overrides).not_to have_key("stock")

      patch location_path(town), params: { location: { name: "New Tule" } }
      expect(town.reload.name).to eq("New Tule")
    end

    it "explores a dungeon: enter, move, fight or wave off" do
      cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
      cave = generate("goblin_cave", on: cave_node)
      campaign.update!(current_node: cave_node)
      post enter_location_path(cave)
      expect(cave.reload.progress["current"]).to eq(cave.view["entrance"])

      next_room = cave.neighbours(cave.view["entrance"]).first
      post move_location_path(cave), params: { room: next_room }
      expect(cave.reload.visited).to include(next_room)

      post move_location_path(cave), params: { room: "room-99" }
      follow_redirect!
      expect(response.body).to include("No such room")

      patch boss_location_path(cave), params: { boss: { monster: "ogre", count: "1" } }
      expect(cave.reload.room(cave.view["boss"])["decision"]["monsters"]).to eq("ogre" => 1)

      post add_room_location_path(cave), params: { room: { name: "Vault", connect: next_room, kind: "treasure", item: "power_ring" } }
      expect(cave.reload.view["rooms"].last).to include("name" => "Vault", "added" => true)
    end

    it "sends everyone back into the dungeon after a fight in it" do
      cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
      cave = generate("goblin_cave", on: cave_node)
      campaign.update!(current_node: cave_node)
      cave.enter!
      battle = BattleRecord.start!(campaign: campaign, characters: [ bartz ], name: "Cave", encounter: { "goblin" => 1 }, seed: 1)
      battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "fled" }, actor: "gm")
      get battle_panel_path(battle)
      expect(response.body).to include("Back to #{cave.name}", "Back to the table")
    end

    it "shows players only the explored part of a dungeon" do
      cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
      cave = generate("goblin_cave", on: cave_node)
      boss_name = cave.room(cave.view["boss"])["name"]
      campaign.update!(current_node: cave_node)
      post enter_location_path(cave)
      sit(bartz.id)
      get location_path(cave)
      expect(response.body).to include("Entrance")
      expect(response.body).not_to include(ERB::Util.html_escape(boss_name)) unless cave.seen_by_players?(cave.view["boss"])
    end
  end

  describe "the books" do
    it "shows a template with an example, and rerolls the example" do
      get world_gazetteer_location_template_path(world, "goblin_cave")
      expect(response.body).to include("Goblin cave", "floorplan", "Goblin Cave", "Another example")
      get world_gazetteer_location_template_path(world, "village", seed: 7)
      expect(response.body).to include("skyline", "seed=8", "People", "For sale")
      village = Generators::Town.generate(seed: 7, template: world.location_templates.find_by!(slug: "village").settings,
                                          tables: world.location_templates.find_by!(slug: "village").table_entries)
      expect(response.body).to include(ERB::Util.html_escape(village["npcs"].first["hook"]))
    end

    it "warns when a template has nothing to draw some things from" do
      empty = World.create!(name: "Empty", slug: "empty")
      empty.location_templates.create!(name: "Hamlet", slug: "hamlet", kind: "town", config: {})
      get world_gazetteer_location_template_path(empty, "hamlet")
      expect(response.body).to include("No town names, names, hooks, service names, buildings, and stock tables", "Stranger 1")
    end

    it "has CRUD for generator tables and templates" do
      post world_generation_generator_tables_path(world), params: { generator_table: {
        name: "Sea names", kind: "town_names", entries: { "0" => { text: "Port Nerve", weight: "2" }, "1" => { text: "" } }
      } }
      expect(response).to redirect_to(world_generation_generator_table_path(world, "sea_names"))
      expect(world.generator_tables.find_by!(slug: "sea_names").entries).to eq([ { "text" => "Port Nerve", "weight" => 2 } ])

      post world_gazetteer_location_templates_path(world), params: { location_template: {
        name: "Harbour", kind: "town",
        config: { services: { inn: "100", shop: "100", guild: "0", temple: "0" }, npcs_min: "2", npcs_max: "4",
                  stock_min: "3", stock_max: "5", buildings_min: "6", buildings_max: "9", tables: [ "", "sea_names", "given_names" ] }
      } }
      harbour = world.location_templates.find_by!(slug: "harbour")
      expect(response).to redirect_to(world_gazetteer_location_template_path(world, harbour))
      follow_redirect!
      expect(response.body).to include("Port Nerve")
    end
  end
end
