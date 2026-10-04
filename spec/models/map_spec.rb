# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The pointcrawl map" do
  include ActiveJob::TestHelper
  let(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let(:tule) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true) }
  let(:ruins) { campaign.map_nodes.create!(name: "Ruins", kind: "dungeon", x: 400, y: 300) }
  let(:grasslands) { world.encounter_tables.find_by!(slug: "grasslands") }

  def connect(a, b, **attrs)
    campaign.map_edges.create!({ from_node: a, to_node: b }.merge(attrs))
  end

  describe EncounterTable do
    it "turns form rows into weighted groups" do
      table = world.encounter_tables.new(name: "Test", terrain: "plains", entries: {
        "0" => { "weight" => "2", "monster" => "goblin", "count" => "3", "monster_2" => "wolf", "count_2" => "1" },
        "1" => { "weight" => "", "monster" => "", "count" => "" }
      })
      expect(table.entries).to eq([ { "weight" => 2, "monsters" => { "goblin" => 3, "wolf" => 1 } } ])
      expect(table).to be_valid
    end

    it "validates monsters against the Bestiary and group sizes" do
      table = world.encounter_tables.new(name: "Bad", terrain: "plains", entries: [ { weight: 0, monsters: { dragon: 12 } } ])
      expect(table).not_to be_valid
      expect(table.errors[:entries]).to include(/weight/, /dragon is not in the Bestiary/, /count must be 1–8/)
      expect(world.encounter_tables.new(name: "Empty", terrain: "plains", entries: [])).not_to be_valid
    end
  end

  describe MapEdge do
    it "joins two different places on the same map, once" do
      connect(tule, ruins)
      expect { connect(ruins, tule) }.to raise_error(ActiveRecord::RecordInvalid, /already connected/)
      expect { connect(tule, tule) }.to raise_error(ActiveRecord::RecordInvalid, /different place/)
      other = world.campaigns.create!(name: "Other").map_nodes.create!(name: "Far", x: 1, y: 1)
      expect { connect(tule, other) }.to raise_error(ActiveRecord::RecordInvalid, /another map/)
    end

    it "is visible to players only once both ends are" do
      edge = connect(tule, ruins)
      expect(edge).not_to be_visible
      ruins.update!(visible: true)
      expect(edge.reload).to be_visible
    end
  end

  describe "travel" do
    before { campaign.place_party!(tule) }

    it "moves the party, reveals the destination and tells the table" do
      connect(tule, ruins, travel_event: "Wind hisses through the stones.")
      expect(campaign.travel!(tule.edges.first)).to be_nil
      expect(campaign.reload.current_node).to eq(ruins)
      expect(ruins.reload).to be_visible
      expect(campaign.messages.where(scope: "table").last(2).map(&:body)).to eq([ "The party travels from Tule to Ruins.", "Wind hisses through the stones." ])
      expect(campaign.messages.where(scope: "table").last).to be_dialogue # the travel event is narrated in the dialogue box
    end

    it "refuses blocked paths and paths that don't start here" do
      connect(tule, ruins, state: "blocked")
      expect { campaign.travel!(tule.edges.first) }.to raise_error(Refusal, /blocked/)
      far = campaign.map_nodes.create!(name: "Far", x: 900, y: 600)
      path = connect(ruins, far)
      expect { campaign.travel!(path) }.to raise_error(Refusal, /doesn't start here/)
      expect(campaign.reload.current_node).to eq(tule)
    end

    it "always rolls an encounter on a dangerous path, from the table, with the campaign's RNG" do
      connect(tule, ruins, state: "dangerous", encounter_table: grasslands)
      rng_before = campaign.rng
      rolled = campaign.travel!(tule.edges.first)

      expected_state, expected = Pointcrawl::Encounters.roll(rng_before, grasslands.entries, "dangerous")
      expect(rolled).to eq(expected)
      expect(campaign.reload.rng).to eq(expected_state)
      expect(campaign.pending_encounter).to eq("table" => "Grasslands", "monsters" => expected, "terrain" => "normal")
      expect(campaign.messages.where(scope: "table").last.body).to start_with("Encounter! ")
    end

    it "starts the pending encounter as a battle for the party, the fallen KO'd, or lets the GM wave it off" do
      bartz = campaign.characters.create!(name: "Bartz", job: world.jobs.find_by!(slug: "knight"))
      campaign.characters.create!(name: "Down", job: world.jobs.first, hp: 0)
      connect(tule, ruins, state: "dangerous", encounter_table: grasslands)
      campaign.travel!(tule.edges.first)

      battle = campaign.start_pending_encounter!
      expect(battle.name).to eq("Grasslands")
      expect(battle.party.map { |u| [ u["name"], u["hp"].zero? ] }).to eq([ [ bartz.name, false ], [ "Down", true ] ])
      expect(campaign.reload.pending_encounter).to be_nil

      campaign.update!(pending_encounter: { "table" => "X", "monsters" => { "goblin" => 1 } })
      campaign.wave_off_encounter!
      expect(campaign.reload.pending_encounter).to be_nil
      expect(campaign.messages.last.body).to eq("The GM waves off the encounter.")
    end
  end

  describe "broadcasts" do
    it "re-renders the stage's map per audience, leaving hidden places out of the players' copy" do
      tule
      campaign.show_map!
      expect { refreshing_the_table { ruins } }.to have_broadcasted_to(stream(campaign, :gm)).with(a_string_including("table_map", "Ruins"))
      expect { refreshing_the_table { ruins.update!(notes: "trap") } }.to have_broadcasted_to(stream(campaign, :players)).with(satisfy { |html| html.include?("table_map") && !html.include?("Ruins") && html.include?("Tule") })
    end
  end
end
