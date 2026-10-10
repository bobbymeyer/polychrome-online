# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Locations", type: :request do
  let!(:world) { base_world }
  let(:campaign) { base_campaign }
  let!(:bartz) { base_character(campaign, name: "Bartz") }
  let(:node) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100) }


  def generate(template_slug, on: node)
    sit(campaign, "gm")
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
    sit(campaign, bartz)
    get location_path(town)
    expect(response).to have_http_status(:not_found)

    node.update!(visible: true)
    get location_path(town)
    expect(response).to have_http_status(:ok)
    hooks = town.view["npcs"].map { |n| n["hook"] }
    expect(response.body).not_to include(*hooks.map { |h| ERB::Util.html_escape(h) })
    # Townsfolk couplets are everyone's: their memory and their wish.
    folk = town.townsfolk.first
    expect(page.css(".couplet").map(&:text).join).to include(town.fill_in(folk["memory"]), town.fill_in(folk["wish"]))
    expect(response.body).not_to include("Reroll", "seed")
  end

  it "keeps the GM controls to the GM" do
    town = generate("village")
    sit(campaign, bartz)
    post location_reroll_path(town)
    expect(response).to have_http_status(:see_other) # the GM seat's: turned back with a word
    post location_pins_path(town), params: { key: "npc-0" }
    expect(response).to have_http_status(:see_other)
  end

  describe "as GM" do
    it "rerolls, pins and makes townsfolk real NPCs" do
      town = generate("village")
      first = town.view["npcs"].first
      post location_pins_path(town), params: { key: first["key"] }
      expect(campaign.npcs.find_by!(location_key: first["key"]).name).to eq(first["name"])

      post location_reroll_path(town)
      follow_redirect!
      expect(response.body).to include("Rerolled", first["name"])

      delete location_pin_path(town, first["key"])
      expect(flash[:notice]).to eq("Unpinned.")
      expect(campaign.npcs.where(location_key: first["key"])).to be_empty

      post location_npcs_path(town), params: { npc: { name: "Galuf", title: "Old man", description: "Can't remember" } }
      get location_path(town)
      expect(response.body).to include("Galuf", "Can&#39;t remember")
    end

    it "keeps a town's people as the party found them when the world's names change, until the GM lets go" do
      town = generate("village")
      met = town.townsfolk.map { |n| n["name"] }
      campaign.place_party!(node)
      town.location_template.generator_tables.where(kind: "names").find_each do |table|
        table.update!(entries: %w[Aoi Haruto Mei Sora Yui Ren].map { |name| { "text" => name } })
      end
      town = Location.find(town.id)
      expect(town.townsfolk.map { |n| n["name"] }).to eq(met)
      expect(town.changes.pluck("kind")).to include("tables")

      town.revert!("tables")
      expect(Location.find(town.id).townsfolk.map { |n| n["name"] }).not_to eq(met)
    end

    it "sets and resets the stock, and renames" do
      town = generate("village")
      patch location_stock_path(town), params: { stock: { items: [ "", "phoenix_down" ] } }
      expect(town.reload.view["stock"]).to eq([ "phoenix_down" ])
      delete location_stock_path(town)
      expect(town.reload.overrides).not_to have_key("stock")

      patch location_path(town), params: { location: { name: "New Tule" } }
      expect(town.reload.name).to eq("New Tule")
    end

    it "explores a dungeon: enter, move, fight or wave off" do
      cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
      cave = generate("goblin_cave", on: cave_node)
      campaign.update!(current_node: cave_node)
      post location_entry_path(cave)
      expect(cave.reload.progress["current"]).to eq(cave.view["entrance"])
      campaign.reload.wave_off_encounter! # whatever waits at the door bars the way on until it's dealt with

      entrance = cave.view["entrance"]
      next_room = cave.neighbours(entrance).find { |key| !cave.locked?(cave.path_between(entrance, key)) } # not behind a lock
      patch location_position_path(cave), params: { room: next_room }
      expect(cave.reload.visited).to include(next_room)

      patch location_position_path(cave), params: { room: "room-99" }
      follow_redirect!
      expect(response.body).to include("No such room")

      patch location_boss_path(cave), params: { boss: { monster: "ogre", count: "1" } }
      expect(cave.reload.room(cave.view["boss"])["decision"]["monsters"]).to eq("ogre" => 1)
      expect(flash[:notice]).to eq("Boss placed.")
      patch location_boss_path(cave), params: { boss: { monster: "ogre", count: "0" } } # none of them: back to the roll
      expect(flash[:notice]).to eq("The boss is back to what was rolled.")
      expect(cave.reload.overrides).not_to have_key("boss")
      patch location_boss_path(cave), params: { boss: { monster: "wyrm_of_nowhere", count: "1" } }
      follow_redirect!
      expect(response.body).to include("wyrm_of_nowhere isn&#39;t in the Bestiary.")

      post location_rooms_path(cave), params: { room: { name: "Vault", connect: next_room, kind: "treasure", item: "power_ring" } }
      expect(cave.reload.view["rooms"].last).to include("name" => "Vault", "added" => true)
    end

    # Reshaping a dungeon, as a map's places are reshaped: drag a room, join
    # two, cut a way. Each one an override, so each one reverts.
    it "moves rooms and joins and cuts ways, and won't strand a room" do
      cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
      cave = generate("goblin_cave", on: cave_node)

      # Dragged on the floorplan. JSON, as floorplan_editor_controller sends it.
      room = cave.view["rooms"].first["key"]
      patch location_room_path(cave, room), params: { room: { x: 240, y: 90 } }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:no_content)
      expect(cave.reload.room(room).slice("x", "y")).to eq("x" => 240, "y" => 90)

      # Clamped to the sheet rather than refused.
      patch location_room_path(cave, room), params: { room: { x: -50, y: 9_000 } }
      expect(cave.reload.room(room).slice("x", "y")).to eq("x" => 0, "y" => Generators::Dungeon::HEIGHT)

      patch location_room_path(cave, "room-99"), params: { room: { x: 1, y: 1 } }
      follow_redirect!
      expect(response.body).to include("No room room-99 here")

      # Joined from the room's panel.
      far = cave.view["rooms"].find { |r| r["key"] != room && !cave.path_between(room, r["key"]) }["key"]
      post location_ways_path(cave), params: { path: { from: room, to: far } }
      expect(cave.reload.neighbours(room)).to include(far)
      post location_ways_path(cave), params: { path: { from: room, to: far } }
      follow_redirect!
      expect(response.body).to include("already joined")

      # Cut again, and the override it came from goes with it.
      joined = cave.reload.path_between(room, far)
      delete location_way_path(cave, joined["key"])
      expect(cave.reload.neighbours(room)).not_to include(far)
      expect(cave.overrides.fetch("added_paths", [])).to be_empty
      expect(cave.overrides.fetch("removed_paths", [])).to be_empty # it was never the roll's to remove

      # The guard: the way off the entrance is the only way in, so cutting it
      # would strand everything behind it.
      entrance = cave.view["entrance"]
      only_way = cave.view["paths"].find { |pa| [ pa["from"], pa["to"] ].include?(entrance) }
      if cave.neighbours(entrance).one?
        delete location_way_path(cave, only_way["key"])
        follow_redirect!
        expect(response.body).to include("strands")
        expect(cave.reload.path_between(only_way["from"], only_way["to"])).to be_present
      end

      delete location_way_path(cave, "path-nowhere")
      follow_redirect!
      expect(response.body).to include("No way path-nowhere here")
    end

    # The contract between the floorplan and floorplan_editor_controller.js:
    # the hooks it binds to have to be on the page, and only for the GM.
    it "draws the GM an editable floorplan, and the players a picture" do
      cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
      cave = generate("goblin_cave", on: cave_node)
      room = cave.view["rooms"].first
      way = cave.view["paths"].first

      get location_path(cave)
      expect(response.body).to include("floorplan--editor", %(data-controller="floorplan-editor"))
      expect(response.body).to include(%(data-floorplan-room="#{room['key']}"), %(data-update-url="#{location_room_path(cave, room['key'])}"))
      expect(response.body).to include(%(data-floorplan-path="#{way['key']}"), %(data-floorplan-from="#{way['from']}"))
      expect(page.at("turbo-frame#room_panel")).to be_present
      expect(response.body).to include("Drag a room to move it")

      # The panel the controller loads into that frame.
      get location_room_path(cave, room["key"])
      expect(response.body).to include(room["name"], "Connect to", "Ways out", "Cut")

      sit(campaign, bartz)
      get location_path(cave)
      expect(response.body).not_to include("floorplan--editor", "data-floorplan-room", "floorplan-editor")
    end

    it "forgets a dungeon's shape on a reroll, and keeps its pins and added rooms" do
      cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
      cave = generate("goblin_cave", on: cave_node)
      room = cave.view["rooms"].first["key"]

      post location_pins_path(cave), params: { key: room }
      post location_rooms_path(cave), params: { room: { name: "Vault", connect: room, kind: "treasure", item: "power_ring" } }
      patch location_room_path(cave, room), params: { room: { x: 240, y: 90 } }
      far = cave.reload.view["rooms"].find { |r| r["key"] != room && !cave.path_between(room, r["key"]) }["key"]
      post location_ways_path(cave), params: { path: { from: room, to: far } }

      expect(cave.reload.overrides.keys).to include("moved_rooms", "added_paths", "pins", "added_rooms")
      post location_reroll_path(cave)
      overrides = cave.reload.overrides
      expect(overrides.keys).not_to include("moved_rooms", "added_paths", "removed_paths")
      expect(overrides.keys).to include("pins", "added_rooms") # those are the GM's writing, not the layout
      expect(cave.view["rooms"].map { |r| r["name"] }).to include("Vault")
    end

    # The elaboration dial (Generators::Elaboration). The promise the GM is
    # being asked to trust: turning it never touches what they pinned.
    it "elaborates a dungeon around its pinned core, and takes it all back" do
      cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
      cave = generate("goblin_cave", on: cave_node)
      core = cave.view["rooms"].map { |r| r.slice("key", "name", "decision", "depth", "x", "y") }
      ways = cave.view["paths"].size

      patch location_elaboration_path(cave), params: { level: "3" }
      expect(flash[:notice]).to eq("Elaborated to 3.")
      grown = cave.reload.view
      expect(grown["rooms"].size).to eq(core.size + 6)
      expect(grown["paths"].size).to be > ways
      # Every pinned room, word for word and pixel for pixel.
      expect(grown["rooms"].first(core.size).map { |r| r.slice("key", "name", "decision", "depth", "x", "y") }).to eq(core)
      expect(grown["rooms"].last(6)).to all(include("elaborated" => true))

      get location_path(cave)
      expect(response.body).to include("is-elaborated", "6 of these #{grown['rooms'].size} rooms are the dial") # the apostrophe is escaped in the page

      # Listed as one change, and reverting takes the whole lot back.
      change = cave.changes.find { |c| c["kind"] == "elaboration" }
      expect(change["summary"]).to eq("Elaborated to 3 of 5 (6 rooms added)")
      cave.revert!("elaboration")
      expect(cave.reload.view["rooms"].map { |r| r.slice("key", "name", "decision", "depth", "x", "y") }).to eq(core)
      expect(cave.overrides).not_to have_key("elaboration")
    end

    it "keeps an elaborated room the GM pinned as the dial rises, and through a reroll" do
      cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
      cave = generate("goblin_cave", on: cave_node)

      patch location_elaboration_path(cave), params: { level: "1" }
      room = cave.reload.view["rooms"].find { |r| r["elaborated"] }
      post location_pins_path(cave), params: { key: room["key"] }
      expect(cave.reload.pinned?(room["key"])).to be(true)

      # Turning it up appends: the pinned room is still that room.
      patch location_elaboration_path(cave), params: { level: "4" }
      expect(cave.reload.room(room["key"])).to include("name" => room["name"], "decision" => room["decision"])

      # A level is not a layout, so unlike moved rooms and joined ways it
      # survives a reroll.
      post location_reroll_path(cave)
      expect(cave.reload.elaboration).to eq(4)
      expect(cave.view["rooms"].count { |r| r["elaborated"] }).to eq(8)
    end

    it "has no dial for a town" do
      town = generate("village")
      get location_path(town)
      expect(response.body).not_to include("Elaboration")
      patch location_elaboration_path(town), params: { level: "3" }
      follow_redirect!
      expect(response.body).to include("is a town")
    end

    it "lists a reshaped dungeon's changes and takes each one back" do
      cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
      cave = generate("goblin_cave", on: cave_node)
      room = cave.view["rooms"].first["key"]
      far = cave.view["rooms"].find { |r| r["key"] != room && !cave.path_between(room, r["key"]) }["key"]
      cut = cave.view["paths"].find { |pa| cave.rooms_off_the_entrance(cave.view["paths"] - [ pa ]).empty? }

      cave.move_room!(room, x: 240, y: 90)
      cave.connect_rooms!(room, far)
      cave.cut_path!(cut["key"]) if cut

      kinds = cave.reload.changes.map { |c| c["kind"] }
      expect(kinds).to include("moved", "path")
      expect(kinds).to include("cut") if cut
      expect(cave.changes.map { |c| c["summary"] }.join).to include("Moved", "Joined")

      cave.changes.each { |c| cave.revert!(c["kind"], c["key"]) }
      expect(cave.reload.overrides.keys).not_to include("moved_rooms", "added_paths", "removed_paths")
      expect(cave.view["paths"].size).to eq(cave.generated["paths"].size)
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
      post location_entry_path(cave)
      sit(campaign, bartz)
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
      expect(page.text).to include(village["npcs"].first["hook"])
      expect(page.at(".couplet")).to be_present
    end

    it "reports what a template makes over a hundred rolls" do
      get world_gazetteer_location_template_path(world, "goblin_cave")
      expect(response.body).to include(world_gazetteer_location_template_report_path(world, "goblin_cave"))

      get world_gazetteer_location_template_report_path(world, "goblin_cave")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("A hundred rolls", "Sizes", "Rooms", "Encounter:", "Room events", "Fork costs", "What they were", "How they fell", "Came up")

      get world_gazetteer_location_template_report_path(world, "village")
      expect(response.body).to include("Townsfolk", "Inn: 100%", "Town names", "Nothing: every roll drew from a table.")

      empty = World.create!(name: "Empty", slug: "empty")
      empty.location_templates.create!(name: "Hamlet", slug: "hamlet", kind: "town", config: {})
      get world_gazetteer_location_template_report_path(empty, "hamlet")
      expect(response.body).to include("Town name: 100%", "Townsperson&#39;s name: 100%")
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
