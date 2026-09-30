# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

RSpec.describe "Clocks and secrets", type: :request do
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Pulp", gm: @admin) }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:town) { campaign.locations.create!(location_template: village, seed: 11) }
  let!(:node) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true, location: town) }
  let(:road) { campaign.map_nodes.create!(name: "Road", kind: "field", x: 300, y: 100, visible: true) }
  let(:burning) { town.modes.find_by!(key: "burning") }
  let(:hero) { campaign.characters.create!(name: "Rook", job: world.jobs.find_by!(slug: "knight"), starting_level: 10) }

  def sit(seat)
    post campaign_table_seat_path(campaign), params: { seat: seat.respond_to?(:id) ? seat.id : seat }
  end

  before do
    sit("gm")
    town.add_mode!("name" => "Burning", "line" => "Smoke over the rooftops: Tule is burning.")
  end

  describe "clocks" do
    it "fills on what the party does, and a full clock sets a place burning" do
      post campaign_clocks_path(campaign), params: { clock: { name: "The Syndicate torches Tule", segments: "3", public: "1",
                                                              triggers: [ "", "rest", "travel" ], when_full: burning.id } }
      clock = campaign.clocks.sole
      expect(clock).to have_attributes(segments: 3, triggers: %w[rest travel], location: town, location_mode: burning, public: true)

      rest_the_night(campaign)
      expect(clock.reload.filled).to eq(1)
      expect(campaign.messages.where(body: "The Syndicate torches Tule: 1 of 3 (the party rested).")).to exist

      campaign.place_party!(road)
      edge = campaign.map_edges.create!(from_node: road, to_node: node)
      campaign.reload.travel!(edge)
      expect(clock.reload.filled).to eq(2)

      post campaign_clock_ticks_path(campaign, clock), params: { by: 1 }
      expect(clock.reload).to be_full
      expect(town.reload.current_mode["name"]).to eq("Burning")
      expect(campaign.messages.order(:id).last(2).map(&:body)).to eq([ "The Syndicate torches Tule: it has happened.", "Smoke over the rooftops: Tule is burning." ])
      # It stops the table: the deadline card, with the date and what the place has become.
      filled = campaign.messages.find_by!(body: "The Syndicate torches Tule: it has happened.")
      expect(filled).to have_attributes(cue: "deadline", data: { "date" => campaign.world.date(campaign.day), "clock" => "The Syndicate torches Tule",
                                                                  "line" => "The Syndicate torches Tule: it has happened.",
                                                                  "place" => "Tule: Burning" })
      get campaign_table_path(campaign)
      expect(response.body).to include('data-controller="dialogue recap deadline awakening"', 'class="deadline-stage"',
                                       "data-chat-line-cue-value=\"deadline\"", "data-chat-line-card-value=")

      rest_the_night(campaign)
      expect(clock.reload.filled).to eq(3) # a full clock stays full

      post campaign_clock_ticks_path(campaign, clock), params: { by: -1 }
      expect(clock.reload).to have_attributes(filled: 2, full_at: nil)
      expect(town.reload.mode).to eq("burning") # winding back doesn't put the fire out
    end

    it "ticks on a failed check, and keeps a hidden clock off the table until it fills" do
      clock = campaign.clocks.create!(name: "The guards close in", segments: 2, triggers: %w[failed_check], full_line: "Whistles in the street: the guards are here.")
      20.times do
        campaign.check!(characters: [ hero ], stat: "agi", difficulty: "heroic")
        break if clock.reload.filled.positive?
      end
      expect(clock.filled).to eq(1)
      expect(campaign.messages.where("body LIKE ?", "The guards close in%")).to be_empty

      clock.tick!
      expect(campaign.messages.last.body).to eq("Whistles in the street: the guards are here.")
    end

    it "shows public clocks to the players, and only the GM the hidden ones" do
      campaign.clocks.create!(name: "Storm rolls in", segments: 4, public: true, filled: 2)
      campaign.clocks.create!(name: "The traitor acts", segments: 4)
      get campaign_table_path(campaign)
      expect(response.body).to include("Storm rolls in", "The traitor acts", "Set the clock")

      sit(hero)
      get campaign_table_path(campaign)
      expect(response.body).to include("Storm rolls in", 'aria-label="2 of 4"')
      expect(response.body).not_to include("The traitor acts")
    end

    it "sends players only public clocks when one changes" do
      hidden = campaign.clocks.create!(name: "The traitor acts", segments: 4)
      streams = capture_turbo_stream_broadcasts([ campaign, :players ]) { refreshing_the_table { hidden.tick! } }
      expect(streams.map { |s| s["target"] }).to include("party_knows")
      expect(streams.map(&:to_html).join).not_to include("The traitor acts")
    end

    it "is the GM's alone" do
      sit(hero)
      post campaign_clocks_path(campaign), params: { clock: { name: "Mine", segments: 4 } }
      expect(response).to have_http_status(:forbidden)
    end

    it "only switches one of the campaign's own places, whatever the form sends" do
      elsewhere = world.campaigns.create!(name: "Elsewhere", gm: @admin).locations.create!(location_template: village, seed: 3)
      flooded = elsewhere.add_mode!("name" => "Flooded")
      expect(campaign.clocks.new(name: "x", segments: 4, location_mode: flooded)).not_to be_valid

      post campaign_clocks_path(campaign), params: { clock: { name: "Rain", segments: "4", when_full: flooded.id } }
      expect(campaign.clocks.find_by!(name: "Rain").location_mode).to be_nil
    end
  end

  it "lets the GM pass time at the table, and shows everyone the time" do
    patch campaign_time_path(campaign), params: { parts: 2 }
    expect(campaign.reload.time_of_day).to eq("dusk")
    patch campaign_time_path(campaign), params: { until: "dawn" }
    expect(campaign.reload).to have_attributes(day: 2, time_of_day: "dawn")
    sit(hero)
    get campaign_table_path(campaign)
    expect(response.body).to include(%(<p class="table-time__date">Day 2</p>), %(<p class="table-time__part">dawn</p>))
    patch campaign_time_path(campaign), params: { parts: 1 }
    expect(response).to have_http_status(:forbidden)
  end

  describe "secrets" do
    it "are kept in prep, revealed at the table, and remembered in the recap" do
      post campaign_secrets_path(campaign), params: { secret: { body: "The mayor pays the goblins.", location_id: town.id, npc_id: "" } }
      secret = campaign.secrets.sole
      expect(secret).to have_attributes(location: town, revealed_at: nil)
      get campaign_prep_path(campaign)
      expect(response.body).to include("The mayor pays the goblins.", "Reveal")

      sit(hero)
      get campaign_table_path(campaign)
      expect(response.body).not_to include("The mayor pays the goblins.")

      sit("gm")
      post campaign_secret_revelation_path(campaign, secret)
      expect(secret.reload).to be_revealed
      expect(campaign.messages.last.body).to eq("The party learns: The mayor pays the goblins.")

      sit(hero)
      get campaign_table_path(campaign)
      expect(response.body).to include("The party knows", "The mayor pays the goblins.")
      expect(Recap.for(campaign).learned).to include("The mayor pays the goblins.")

      sit("gm")
      delete campaign_secret_revelation_path(campaign, secret)
      expect(secret.reload).not_to be_revealed
    end

    it "come out through a field ability that uncovers them, the one about where the party is first" do
      campaign.secrets.create!(body: "The well is poisoned.")
      here = campaign.secrets.create!(body: "Tule's elder is the Syndicate's man.", location: town)
      campaign.place_party!(node)
      ability = world.abilities.create!(slug: "ask_around", name: "Ask Around", kind: "field", target: "self", field_skill: "persuasion",
                                        field_outcome: "uncover", field_difficulty: "easy", effects: [])
      hero.job.update!(field_ability: ability.slug)
      20.times do
        hero.reload.update!(field_used: false)
        use = FieldUse.request!(hero.reload)
        use.approve!(difficulty: "easy")
        break if here.reload.revealed?
      end
      expect(here.reload).to have_attributes(revealed_by: "Rook's Ask Around")
      expect(campaign.messages.where(body: "Rook's Ask Around: the party learns: Tule's elder is the Syndicate's man.")).to exist
    end
  end
end
