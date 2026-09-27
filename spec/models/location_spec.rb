# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe Location do
  let(:world) { Seeds::BaseWorld.run }
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
      expect(table.errors[:entries]).to include(/excalibur is not in the Armory/, /doesn't use: text/)

      table = world.generator_tables.new(name: "Buildings", kind: "buildings",
                                         entries: { "0" => { "text" => "Hut", "width" => "40", "height" => "", "roof" => "spire" } })
      expect(table.entries).to eq([ { "text" => "Hut", "width" => 40, "roof" => "spire" } ])
      expect(table).not_to be_valid
      expect(table.errors[:entries]).to include(/unknown roof spire/)
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
      expect(village.table_entries.keys).to match_array(%w[place_names names hooks service_names buildings stock])
      names = village.table_entries["place_names"].map { |e| e["text"] }
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
      expect(boss_room["decision"]).to eq("kind" => "boss", "monsters" => { "ogre" => 2 })

      key = dungeon.add_room!(name: "Secret Library", connect: entrance, decision: { "kind" => "treasure", "item" => "power_ring" })
      expect(dungeon.neighbours(entrance)).to include(key)
      expect { dungeon.add_room!(name: "X", connect: entrance, decision: { "kind" => "encounter", "monsters" => { "dragon" => 1 } }) }
        .to raise_error(ArgumentError, /Bestiary/)
    end

    it "can only be explored while the party is there, and is left when they travel on" do
      dungeon.enter!
      road = campaign.map_nodes.create!(name: "Road", kind: "field", x: 2, y: 2)
      campaign.travel!(campaign.map_edges.create!(from_node: campaign.current_node, to_node: road))
      expect(dungeon.reload.progress["current"]).to be_nil
      expect(dungeon.visited).to include(entrance)
      expect { dungeon.enter! }.to raise_error(ArgumentError, /isn't at/)
    end

    it "is explored room by room, each room playing its decision at the table" do
      dungeon.enter!
      expect(dungeon.progress["current"]).to eq(entrance)
      expect(campaign.messages.first.body).to include("the party enters Entrance")

      far = dungeon.view["rooms"].find { |r| !dungeon.neighbours(entrance).include?(r["key"]) && r["key"] != entrance }
      expect { dungeon.move_to!(far["key"]) }.to raise_error(ArgumentError, /isn't next to/)

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
          expect(campaign.reload.pending_encounter).to eq("table" => "#{dungeon.name}: Test 1", "monsters" => { "goblin" => 2 })
        when "treasure"
          dungeon.take_treasure!(key)
          expect(campaign.quantity_of(world.items.find_by!(slug: "potion"))).to eq(1)
          expect { dungeon.take_treasure!(key) }.to raise_error(ArgumentError)
        end
      end
      expect(rooms).to be_present
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
end
