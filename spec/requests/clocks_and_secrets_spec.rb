# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

RSpec.describe "Clocks and secrets", type: :request do
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  let!(:world) { base_world }
  let(:campaign) { base_campaign(name: "Pulp", gm: @admin) }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:town) { campaign.locations.create!(location_template: village, seed: 11) }
  let!(:node) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true, location: town) }
  let(:road) { campaign.map_nodes.create!(name: "Road", kind: "field", x: 300, y: 100, visible: true) }
  let(:burning) { town.map_node.modes.find_by!(key: "burning") }
  let(:hero) { base_character(campaign, name: "Rook", starting_level: 10) }


  before do
    sit(campaign, "gm")
    town.map_node.add_mode!("name" => "Burning", "line" => "Smoke over the rooftops: Tule is burning.")
  end

  describe "clocks" do
    it "offers the modes a clock can set off by place, and not those that follow the hours" do
      town.map_node.add_mode!("name" => "By night", "times" => %w[night])
      get campaign_prep_path(campaign)
      options = page.css("option").map(&:text)
      expect(options).to include("Tule: Burning")
      expect(options).not_to include("Tule: By night")
    end

    it "fills on what the party does, and a full clock sets a place burning" do
      post campaign_clocks_path(campaign), params: { clock: { name: "The Syndicate torches Tule", segments: "3", public: "1",
                                                              triggers: [ "", "rest", "travel" ], when_full: burning.id } }
      clock = campaign.clocks.sole
      expect(clock).to have_attributes(segments: 3, triggers: %w[rest travel], place: node, mode: burning, public: true)

      rest_the_night(campaign)
      expect(clock.reload.filled).to eq(1)
      expect(campaign.messages.where(body: "The Syndicate torches Tule: 1 of 3 (the party rested).")).to exist

      campaign.place_party!(road)
      edge = campaign.map_edges.create!(from_node: road, to_node: node)
      campaign.reload.travel!(edge)
      expect(clock.reload.filled).to eq(2)

      post campaign_clock_ticks_path(campaign, clock), params: { by: 1 }
      expect(clock.reload).to be_full
      expect(town.map_node.reload.current_mode["name"]).to eq("Burning")
      expect(campaign.messages.order(:id).last(2).map(&:body)).to eq([ "The Syndicate torches Tule: it has happened.", "Smoke over the rooftops: Tule is burning." ])
      # It stops the table: the deadline card, with the date and what the place has become.
      filled = campaign.messages.find_by!(body: "The Syndicate torches Tule: it has happened.")
      expect(filled).to have_attributes(cue: "deadline", data: { "date" => campaign.world.date(campaign.day), "clock" => "The Syndicate torches Tule",
                                                                  "line" => "The Syndicate torches Tule: it has happened.",
                                                                  "place" => "Tule: Burning" })
      get campaign_table_path(campaign)
      expect(page.at("[data-controller~=moment][data-controller~=whisper-toast][data-controller~=recap][data-controller~=dialogue]")).to be_present
      expect(page.at(".deadline-stage")["data-moment-cue"]).to eq("deadline")
      expect(page.at("[data-chat-line-cue-value=deadline]")["data-chat-line-card-value"]).to be_present

      rest_the_night(campaign)
      expect(clock.reload.filled).to eq(3) # a full clock stays full

      post campaign_clock_ticks_path(campaign, clock), params: { by: -1 }
      expect(clock.reload).to have_attributes(filled: 2, full_at: nil)
      expect(town.map_node.reload.mode).to eq("burning") # winding back doesn't put the fire out
    end

    it "lets a check the GM calls make something happen on a success, once, whoever made it" do
      sit(campaign, "gm")
      campaign.call_controls!("check") # the form comes to the table once Check is called
      get campaign_table_path(campaign)
      expect(response.body).to include("On a success")
      gil = campaign.gil
      20.times do
        post campaign_checks_path(campaign), params: { check: { characters: [ hero.id ], stat: "agi", difficulty: "easy", outcome: "money", amount: "15" } }
        break if campaign.reload.gil > gil
      end
      expect(campaign.gil).to eq(gil + 15)
      expect(campaign.messages.last.body).to eq("#{hero.name}: 15 gil.")

      post campaign_checks_path(campaign), params: { check: { characters: [ hero.id ], stat: "agi", difficulty: "easy", outcome: "sneak" } }
      expect(flash[:alert]).to eq("There's no encounter on the road to get past")
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
      get campaign_prep_path(campaign) # the GM's list is Prep's
      expect(response.body).to include("Storm rolls in", "The traitor acts", "Set the clock")
      get campaign_table_path(campaign)
      expect(response.body).to include("Storm rolls in") # the public one, in what the party knows
      expect(response.body).not_to include("Set the clock")

      at_the_table(campaign, as: hero)
      expect(response.body).to include("Storm rolls in")
      expect(page.at("[aria-label='2 of 4']")).to be_present
      expect(response.body).not_to include("The traitor acts")
    end

    it "sends players only public clocks when one changes" do
      hidden = campaign.clocks.create!(name: "The traitor acts", segments: 4)
      # A refresh carries nothing: each seat fetches its own table again, and a player's has no hidden clock.
      streams = capture_turbo_stream_broadcasts([ campaign, :table_refresh ]) { refreshing_the_table { hidden.tick! } }
      expect(streams.map { |s| s["action"] }).to eq([ "refresh" ])
      expect(streams.map(&:to_html).join).not_to include("The traitor acts")
      at_the_table(campaign, as: hero)
      expect(response.body).not_to include("The traitor acts")
    end

    it "is the GM's account's: a player is turned away, and the GM seated as a player is not" do
      sit(campaign, hero) # the GM, playing a character for a moment: Prep is still theirs
      post campaign_clocks_path(campaign), params: { clock: { name: "Mine", segments: 4 } }
      expect(campaign.clocks.find_by(name: "Mine")).to be_present

      sign_in_as(make_user("Player"))
      post campaign_clocks_path(campaign), params: { clock: { name: "Theirs", segments: 4 } }
      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to include("not yours")
      expect(campaign.clocks.find_by(name: "Theirs")).to be_nil
    end

    it "only switches one of the campaign's own places, whatever the form sends" do
      elsewhere = world.campaigns.create!(name: "Elsewhere", gm: @admin).map_nodes.create!(name: "Far", kind: "town", x: 1, y: 1)
      flooded = elsewhere.add_mode!("name" => "Flooded")
      expect(campaign.clocks.new(name: "x", segments: 4, mode: flooded)).not_to be_valid

      post campaign_clocks_path(campaign), params: { clock: { name: "Rain", segments: "4", when_full: flooded.id } }
      expect(campaign.clocks.find_by!(name: "Rain").mode).to be_nil
    end
  end

  it "lets the GM pass time at the table, as a row of the things to do here, and shows everyone the time" do
    get campaign_table_path(campaign)
    expect(response.body).not_to include("Let time pass") # not until the day's doings are called
    campaign.call_controls!("doing")
    get campaign_table_path(campaign)
    ways = page.at("#table_ways")
    expect(ways.key?("hidden")).to be(false)
    expect(ways.css(".pick-row").last.text).to include("Let time pass", "a part of the day") # the last row of the things to do
    expect(ways.text).not_to include("Until #{campaign.almanac.periods.first}") # one press, one part of the day
    patch campaign_time_path(campaign), params: { parts: 2 }
    expect(campaign.reload.time_of_day).to eq("dusk")
    patch campaign_time_path(campaign), params: { until: "the_day" }
    expect(campaign.reload).to have_attributes(day: 2, time_of_day: "dawn")
    at_the_table(campaign, as: hero)
    expect(page.at("p.table-time__date").text).to eq("Day 2")
    expect(page.at("p.table-time__part").text).to eq("dawn")
    patch campaign_time_path(campaign), params: { parts: 1 }
    expect(response).to have_http_status(:see_other) # the GM seat's
  end

  it "keeps clocks and secrets in Prep, and tells the GM at the table when a clock is one tick from full" do
    campaign.clocks.create!(name: "The tide", segments: 4, filled: 3)
    campaign.clocks.create!(name: "The count schemes", segments: 6, filled: 1)
    get campaign_table_path(campaign)
    expect(response.body).not_to include("gm_clocks", "gm_secrets", "gm_tab_clocks", "gm_tab_secrets")
    expect(page.at("#table_now .table-now__clock").text.squish).to eq("The tide is one tick from full · Clocks")
    expect(response.body).to include(campaign_prep_path(campaign, anchor: "clocks"))
    get campaign_prep_path(campaign)
    expect(response.body).to include("gm_clocks", "gm_secrets", "The tide", "The count schemes")
    at_the_table(campaign, as: hero)
    expect(response.body).not_to include("table-now__clock", "one tick from full")
  end

  describe "secrets" do
    it "are kept in prep, revealed at the table, and remembered in the recap" do
      post campaign_secrets_path(campaign), params: { secret: { body: "The mayor pays the goblins.", location_id: town.id, npc_id: "" } }
      secret = campaign.secrets.sole
      expect(secret).to have_attributes(location: town, revealed_at: nil)
      get campaign_prep_path(campaign)
      expect(response.body).to include("The mayor pays the goblins.", "Reveal")

      at_the_table(campaign, as: hero)
      expect(response.body).not_to include("The mayor pays the goblins.")

      sit(campaign, "gm")
      post campaign_secret_revelation_path(campaign, secret)
      expect(secret.reload).to be_revealed
      expect(campaign.messages.last.body).to eq("The party learns: The mayor pays the goblins.")

      at_the_table(campaign, as: hero)
      expect(response.body).to include("The party learns: The mayor pays the goblins.") # the log said it
      expect(page.at("#party_knows").key?("hidden")).to be(true) # nothing moving: the panel waits
      expect(page.at("#party_knows").text).not_to include("The mayor pays the goblins.")
      get campaign_legends_path(campaign)
      expect(response.body).to include("What they found out", "The mayor pays the goblins.")
      expect(Recap.for(campaign).learned).to include("The mayor pays the goblins.")

      sit(campaign, "gm")
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
