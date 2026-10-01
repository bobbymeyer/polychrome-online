# frozen_string_literal: true

require "rails_helper"

RSpec.describe Location do
  let(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:cave) { world.location_templates.find_by!(slug: "goblin_cave") }
  let(:town) { campaign.locations.create!(location_template: village, seed: 11) }
  let(:dungeon) do
    campaign.locations.create!(location_template: cave, seed: 11).tap do |d|
      campaign.update!(current_node: campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 1, y: 1, location: d))
    end
  end

  describe "the books" do
    it "validates generator-table rows against their kind" do
      table = world.generator_tables.new(name: "Bad", kind: "stock", entries: [ { item: "excalibur" }, { text: "Loose text" } ])
      expect(table).not_to be_valid
      expect(table.errors[:entries]).to include(/excalibur is not in the Armory/)
      expect(table.entries).to eq([ { "item" => "excalibur" } ]) # a stock table has no text: that row went

      table = world.generator_tables.new(name: "Buildings", kind: "buildings",
                                         entries: { "0" => { "text" => "Hut", "width" => "40", "height" => "", "roof" => "spire" } })
      expect(table.entries).to eq([ { "text" => "Hut", "width" => 40, "roof" => "spire" } ])
      expect(table).not_to be_valid
      expect(table.errors[:entries]).to include(/unknown roof spire/)
    end

    it "adds pasted lines as rows, by the kind's format, or none if a line doesn't read" do
      names = world.generator_tables.create!(name: "Names", kind: "names", entries: [ { text: "Mira" } ], paste: "Oskar\n\n  Lenne | 3 \n")
      expect(names.entries).to eq([ { "text" => "Mira" }, { "text" => "Oskar" }, { "text" => "Lenne", "weight" => 3 } ])
      expect(names.paste).to be_nil

      loot = world.generator_tables.create!(name: "Loot", kind: "treasure", paste: "Potion\n150 gil | 2")
      expect(loot.entries).to eq([ { "item" => "potion" }, { "gil" => 150, "weight" => 2 } ])

      bad = world.generator_tables.new(name: "Stock", kind: "stock", paste: "potion\nExcalibur")
      expect(bad).not_to be_valid
      expect(bad.errors[:paste]).to include(/line 2: nothing in the Armory is called Excalibur/)
      expect(bad.entries).to be_empty
    end

    it "turns flat template fields into generator settings, with defaults" do
      template = world.location_templates.new(name: "Hamlet", kind: "town", config: {
        "services" => { "inn" => "100", "shop" => "0" }, "npcs_min" => "2", "npcs_max" => "3", "tables" => [ "", "town_names" ]
      })
      expect(template.config).to eq("services" => { "inn" => 100, "shop" => 0 }, "npcs" => [ 2, 3 ], "tables" => [ "town_names" ])
      expect(template.settings).to include("npcs" => [ 2, 3 ], "stock" => [ 4, 6 ])
      expect(template.generator_tables.pluck(:slug)).to eq([ "town_names" ])
      expect(template).to be_valid
    end

    it "rejects nonsense settings" do
      template = world.location_templates.new(name: "Pit", kind: "dungeon", config: { "rooms_min" => "9", "rooms_max" => "3", "boss_monster" => "dragon" })
      expect(template).not_to be_valid
      expect(template.errors[:config]).to include(/rooms must be a range/, /boss dragon is not in the Bestiary/)
    end

    it "draws only from the template's chosen tables" do
      expect(village.table_entries.keys).to match_array(%w[town_names names hooks memories wishes service_names buildings stock])
      names = village.table_entries["town_names"].map { |e| e["text"] }
      expect(names).to include("Tule")
      expect(names).not_to include("Wind Shrine")
    end
  end

  describe "a town" do
    it "is generated from template and seed, never stored" do
      expect(town.view).to eq(described_class.find(town.id).view)
      expect(town.view["services"]).not_to be_empty
      expect(town.attributes.keys).not_to include("services", "npcs")
    end

    it "gets its name from the map place when rolled from one" do
      node = campaign.map_nodes.create!(name: "Tule", x: 1, y: 1)
      post_create = campaign.locations.create!(location_template: village, overrides: { "name" => node.name })
      expect(post_create.name).to eq("Tule")
    end

    it "keeps pinned services and pinned NPCs through a reroll" do
      inn = town.view["services"].find { |s| s["kind"] == "inn" }
      npc = town.view["npcs"].first
      town.pin!(inn["key"])
      town.pin!(npc["key"])

      real = campaign.npcs.find_by!(location: town, location_key: npc["key"])
      expect(real).to have_attributes(name: npc["name"], title: npc["title"], description: npc["hook"])

      town.reroll!
      expect(town.seed).not_to eq(11)
      expect(town.view["services"].find { |s| s["kind"] == "inn" }["name"]).to eq(inn["name"])
      expect(town.roster.first["npc"]).to eq(real)
    end

    it "never rolls a second person with a name the cast already has" do
      first, second = town.view["npcs"].first(2)
      campaign.npcs.create!(name: second["name"]) # someone the party already knows, elsewhere
      town.pin!(first["key"])
      shown = town.townsfolk
      expect(shown.first["name"]).to eq(first["name"])
      expect(shown.map { |n| n["name"] }).to eq(shown.map { |n| n["name"] }.uniq)
      expect(shown.second["name"]).not_to eq(second["name"])
      expect(shown.drop(2)).to eq(town.view["npcs"].drop(2)) # nobody else changes
    end

    it "unpins, letting the reroll replace them" do
      npc = town.view["npcs"].first
      town.pin!(npc["key"])
      town.unpin!(npc["key"])
      expect(campaign.npcs.where(location: town)).to be_empty
      expect(town.pinned?(npc["key"])).to be(false)
    end

    it "lists written-in NPCs after the generated ones" do
      galuf = campaign.npcs.create!(name: "Galuf", location: town)
      expect(town.roster.last).to eq("npc" => galuf, "generated" => nil)
    end

    it "lets the GM set the stock, and go back to what was rolled" do
      town.set_stock!(%w[phoenix_down elixir_that_does_not_exist])
      expect(town.stock_items.map(&:slug)).to eq(%w[phoenix_down])
      town.set_stock!(nil)
      expect(town.view["stock"]).to eq(town.generated["stock"])
    end

    it "asks every viewer to refresh when it changes" do
      expect { town.rename!("Tule") }.to have_broadcasted_to(Turbo::StreamsChannel.send(:stream_name_from, town))
    end
  end

  describe "a dungeon" do
    let(:entrance) { dungeon.view["entrance"] }

    it "lets the GM place the boss and add rooms" do
      dungeon.place_boss!("ogre" => "2")
      boss_room = dungeon.room(dungeon.view["boss"])
      expect(boss_room["decision"]).to include("kind" => "boss", "monsters" => { "ogre" => 2 })

      key = dungeon.add_room!(name: "Secret Library", connect: entrance, decision: { "kind" => "treasure", "item" => "power_ring" })
      expect(dungeon.neighbours(entrance)).to include(key)
      expect { dungeon.add_room!(name: "X", connect: entrance, decision: { "kind" => "encounter", "monsters" => { "dragon" => 1 } }) }
        .to raise_error(Refusal, /Bestiary/)
    end

    it "can only be explored while the party is there, and is left when they travel on" do
      dungeon.enter!
      road = campaign.map_nodes.create!(name: "Road", kind: "field", x: 2, y: 2)
      campaign.travel!(campaign.map_edges.create!(from_node: campaign.current_node, to_node: road))
      expect(dungeon.reload.progress["current"]).to be_nil
      expect(dungeon.visited).to include(entrance)
      expect { dungeon.enter! }.to raise_error(Refusal, /isn't at/)
    end

    it "is explored room by room, each room playing its decision at the table" do
      dungeon.enter!
      expect(dungeon.progress["current"]).to eq(entrance)
      expect(campaign.messages.first.body).to include("the party enters Entrance")

      far = dungeon.view["rooms"].find { |r| !dungeon.neighbours(entrance).include?(r["key"]) && r["key"] != entrance }
      expect { dungeon.move_to!(far["key"]) }.to raise_error(Refusal, /isn't next to/)

      next_key = dungeon.neighbours(entrance).first
      dungeon.move_to!(next_key)
      expect(dungeon.visited).to eq([ entrance, next_key ])
    end

    it "narrates events, holds encounters for the GM, and hands treasure over once" do
      rooms = dungeon.view["rooms"].index_by { |r| r["key"] }
      dungeon.update!(progress: { "current" => entrance, "visited" => [ entrance ] })

      event = { "kind" => "event", "text" => "The floor tilts." }
      encounter = { "kind" => "encounter", "monsters" => { "goblin" => 2 } }
      treasure = { "kind" => "treasure", "item" => "potion" }
      [ event, encounter, treasure ].each_with_index do |decision, i|
        key = dungeon.add_room!(name: "Test #{i}", connect: entrance, decision: decision)
        dungeon.update!(progress: dungeon.progress.merge("current" => entrance))
        dungeon.move_to!(key)
        case decision["kind"]
        when "event"
          expect(campaign.messages.last).to have_attributes(body: "The floor tilts.", speaker: nil)
          expect(campaign.messages.last).to be_dialogue
        when "encounter"
          expect(campaign.reload.pending_encounter).to eq("table" => "#{dungeon.name}: Test 1", "monsters" => { "goblin" => 2 }, "terrain" => "rock",
                                                          "location" => dungeon.id, "room" => key)
        when "treasure"
          dungeon.take_treasure!(key)
          expect(campaign.quantity_of(world.items.find_by!(slug: "potion"))).to eq(1)
          expect(campaign.messages.last.cue).to eq("treasure")
          expect { dungeon.take_treasure!(key) }.to raise_error(Refusal)
        end
      end
      expect(rooms).to be_present
    end

    it "leaves a fight the party walked away from in its room, waiting for them" do
      dungeon.enter!
      key = dungeon.add_room!(name: "Guardroom", connect: entrance, decision: { "kind" => "encounter", "monsters" => { "goblin" => 2 } })
      dungeon.move_to!(key)
      expect(campaign.reload.pending_encounter).to include("room" => key)

      dungeon.move_to!(entrance)
      expect(campaign.reload.pending_encounter).to be_nil
      expect(dungeon.resolved?(key)).to be(false)

      dungeon.move_to!(key)
      expect(campaign.reload.pending_encounter).to include("room" => key, "monsters" => { "goblin" => 2 })
    end

    it "deals with a room's ordinary fight when it is won or waved off, not when it is called" do
      create_character(campaign, name: "Bartz") if campaign.characters.none?
      dungeon.enter!
      key = dungeon.add_room!(name: "Guardroom", connect: entrance, decision: { "kind" => "encounter", "monsters" => { "goblin" => 2 } })
      dungeon.move_to!(key)
      expect(dungeon.resolved?(key)).to be(false)

      battle = campaign.reload.start_pending_encounter!
      battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "fled" }, actor: "gm")
      expect(dungeon.reload.resolved?(key)).to be(false)

      dungeon.move_to!(entrance)
      dungeon.move_to!(key)
      campaign.reload.wave_off_encounter!
      expect(campaign.messages.last.body).to eq("The GM waves off the encounter.")
      expect(dungeon.reload.resolved?(key)).to be(true)

      dungeon.move_to!(entrance)
      dungeon.move_to!(key)
      expect(campaign.reload.pending_encounter).to be_nil
    end

    it "offers the way out at the entrance, and names the doors still locked" do
      dungeon.enter!
      out = campaign.ways_on.find { |way| way["label"] == "Leave #{dungeon.name}" }
      expect(out).to be_present
      campaign.make_move!(out["move"])
      expect(dungeon.reload.progress["current"]).to be_nil
      expect(campaign.reload.dungeon_in_progress).to be_nil

      lock = dungeon.view["paths"].find { |p| p["lock"] }
      dungeon.update!(progress: { "current" => lock["from"], "visited" => [ lock["from"] ] })
      campaign.reload
      expect(campaign.locked_ways).to include("#{lock['lock']['name']} (needs #{lock['lock']['key_name']})")
      expect(campaign.ways_on.map { |way| way["move"]["room"] }).not_to include(lock["to"])
    end

    it "says who can use gear found as treasure" do
      bartz = create_character(campaign, name: "Bartz") # a Knight
      sword = world.items.select(&:equipment?).find { |item| !bartz.job.equips?(item) }
      dungeon.enter!
      key = dungeon.add_room!(name: "Armoury", connect: entrance, decision: { "kind" => "treasure", "item" => sword.slug })
      dungeon.move_to!(key)
      expect(dungeon.take_treasure!(key)).to match(/Found #{sword.name} in Armoury\. Nobody can use it as they are; a .+ could\./)
    end

    it "makes the boss room's fight a boss fight" do
      dungeon.enter!
      key = dungeon.add_room!(name: "Throne", connect: entrance, decision: { "kind" => "boss", "monsters" => { "goblin" => 1 } })
      dungeon.move_to!(key)
      expect(campaign.reload.pending_encounter).to include("boss" => true)
      create_character(campaign, name: "Bartz") if campaign.characters.none?
      expect(campaign.start_pending_encounter!).to be_boss
    end

    it "hands over gil treasure to the party's purse" do
      dungeon.enter!
      key = dungeon.add_room!(name: "Strongbox", connect: entrance, decision: { "kind" => "treasure", "gil" => 150 })
      dungeon.move_to!(key)
      expect { dungeon.take_treasure!(key) }.to change { campaign.reload.gil }.by(150)
      expect(campaign.messages.last.body).to eq("Found 150 gil in Strongbox.")
    end

    it "is locked until the party finds the key, which then opens the way for good" do
      lock = dungeon.view["paths"].find { |p| p["lock"] }["lock"]
      key_room = dungeon.view["rooms"].find { |r| r["decision"]["kind"] == "key" }
      expect(key_room["decision"]).to include("lock" => lock["id"], "name" => lock["key_name"])

      # Walk the rooms, never through a shut lock, until every reachable room is visited.
      dungeon.enter!
      walk = lambda do
        loop do
          here = dungeon.reload.progress["current"]
          step = dungeon.neighbours(here).find { |n| !dungeon.visited.include?(n) && !dungeon.locked?(dungeon.path_between(here, n)) }
          step ||= dungeon.neighbours(here).find { |n| !dungeon.locked?(dungeon.path_between(here, n)) && dungeon.neighbours(n).any? { |m| !dungeon.visited.include?(m) && !dungeon.locked?(dungeon.path_between(n, m)) } }
          break unless step

          dungeon.move_to!(step)
          campaign.update!(pending_encounter: nil)
        end
      end
      walk.()
      expect(dungeon.keys_found).to eq([ lock["id"] ])
      expect(campaign.messages.pluck(:body)).to include(a_string_matching(/Found #{Regexp.escape(lock['key_name'])}.*#{Regexp.escape(lock['name'])}/))
      expect(dungeon.visited).not_to include(dungeon.view["boss"])

      # Beside the lock: without the key it would refuse; with it, it opens.
      locked = dungeon.view["paths"].find { |p| p["lock"] && (dungeon.visited.include?(p["from"]) || dungeon.visited.include?(p["to"])) }
      near, far = dungeon.visited.include?(locked["from"]) ? [ locked["from"], locked["to"] ] : [ locked["to"], locked["from"] ]
      dungeon.update!(progress: dungeon.progress.merge("current" => near))
      without = dungeon.progress.merge("keys" => [])
      dungeon.update!(progress: without)
      expect { dungeon.move_to!(far) }.to raise_error(Refusal, /#{Regexp.escape(lock['name'])} bars the way/)
      dungeon.update!(progress: without.merge("keys" => [ lock["id"] ]))
      dungeon.move_to!(far)
      expect(dungeon.unlocked?(lock)).to be(true)
      expect(dungeon.keys_in_hand).to be_empty
      expect(campaign.messages.pluck(:body)).to include(a_string_including("opens #{lock["name"]}. The way is clear."))
      # Each has its jingle.
      expect(campaign.messages.where.not(cue: nil).pluck(:cue).uniq).to include("key", "door")
    end

    it "shows players only the rooms they've been in and the exits out of them" do
      dungeon.enter!
      seen = dungeon.view["rooms"].map { |r| r["key"] }.select { |k| dungeon.seen_by_players?(k) }
      expect(seen).to match_array([ entrance ] + dungeon.neighbours(entrance))
    end

    it "starts exploration over on a reroll" do
      dungeon.enter!
      dungeon.reroll!
      expect(dungeon.progress).to eq({})
    end
  end

  it "points a townsfolk hook at real places: the nearest of each kind by road" do
    tule = campaign.map_nodes.create!(name: "Tule", kind: "town", x: 1, y: 1, location: town)
    near = campaign.map_nodes.create!(name: "Walse", kind: "town", x: 2, y: 2)
    far = campaign.map_nodes.create!(name: "Karnak", kind: "town", x: 3, y: 3)
    cave = campaign.map_nodes.create!(name: "Goblin Hollow", kind: "dungeon", x: 4, y: 4)
    campaign.map_edges.create!(from_node: tule, to_node: near)
    campaign.map_edges.create!(from_node: near, to_node: far)
    campaign.map_edges.create!(from_node: cave, to_node: tule)
    expect(town.fill_in("Needs medicine from {town} before the week is out.")).to eq("Needs medicine from Walse before the week is out.")
    expect(town.fill_in("Knows the old way into {dungeon}.")).to eq("Knows the old way into Goblin Hollow.")
    expect(town.fill_in("Plain as day.")).to eq("Plain as day.")
    cave.destroy!
    expect(town.fill_in("Knows the old way into {dungeon}.")).to eq("Knows the old way into somewhere far off.")
  end
end
