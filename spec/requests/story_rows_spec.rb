# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Story rows: arrival lines, the facts page and the moment", type: :request do
  let!(:world) { base_world }
  let(:campaign) { base_campaign(name: "Pulp", gm: @admin) }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let!(:tule) do
    campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true, location: campaign.locations.create!(location_template: village, seed: 11))
  end
  let(:player) { make_user("Player") }
  let!(:rook) { create_character(campaign, name: "Rook", user: player) }

  before { campaign.update!(current_node: tule) }

  it "writes rows that say when they fit and what they remember, and turns away ones it can't read" do
    post world_generation_generator_tables_path(world), params: { generator_table: {
      name: "Night arrivals", slug: "night_arrivals", kind: "arrivals",
      paste: "A lamp in {place}, {dim|bright}. | town, night, !lamp_seen | lamp_seen\nQuiet. | | | 2"
    } }
    table = world.generator_tables.find_by!(slug: "night_arrivals")
    expect(table.entries).to eq([ { "text" => "A lamp in {place}, {dim|bright}.", "when" => "town, night, !lamp_seen", "sets" => "lamp_seen" },
                                  { "text" => "Quiet.", "weight" => 2 } ])

    patch world_generation_generator_table_path(world, table), params: { generator_table: { entries: [ { text: "x", when: "hurt >= lots" } ] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("isn&#39;t something a row can ask")

    get world_generation_generator_table_path(world, table)
    expect(response.body).to include("Every fact a row can ask about")
    get world_generation_facts_path(world)
    expect(response.body).to include("first_visit", "clock_&lt;name&gt;", "Night arrivals", "dusk")
  end

  it "lets the GM say an offered line, once, and nobody else" do
    note = campaign.narrate("To say, arriving at Tule: “A lamp.”", scope: "gm", data: { "offer" => { "text" => "A lamp.", "sets" => [ { "key" => "lamp_seen", "op" => "=", "value" => "yes" } ] } })

    sign_in_as(player)
    post message_saying_path(note)
    expect(response).to have_http_status(:see_other) # the GM seat's: turned back with a word

    sign_in_as(@admin)
    at_the_table(campaign, as: "gm")
    expect(response.body).to include("Say it")
    post message_saying_path(note)
    expect(campaign.messages.where(scope: "table", kind: "say").pluck(:body)).to eq([ "A lamp." ])
    expect(campaign.flags.find_by!(key: "lamp_seen").value).to eq("yes")
    post message_saying_path(note)
    expect(flash[:alert]).to eq("Already said.")
    expect(campaign.messages.where(scope: "table", kind: "say").count).to eq(1)

    get campaign_prep_path(campaign)
    expect(response.body).to include("The moment", "lamp_seen", "first_visit")
  end

  it "pastes an event with its choice, and lets the GM put it to the table" do
    post world_generation_generator_tables_path(world), params: { generator_table: {
      name: "Road events", slug: "road_events", kind: "events",
      paste: "A cart in the ditch. | road | cart_seen | Help: time 1, money 30; Leave it: tick -> helped_cart"
    } }
    table = world.generator_tables.find_by!(slug: "road_events")
    expect(table.entries.sole).to eq("text" => "A cart in the ditch.", "when" => "road", "sets" => "cart_seen",
                                     "choices" => "Help: time 1, money 30 | Leave it: tick -> helped_cart")

    note = campaign.narrate("An event, on the road: “A cart in the ditch.”", scope: "gm",
                            data: { "offer" => { "text" => "A cart in the ditch.", "flag" => "helped_cart",
                                                 "choices" => [ { "label" => "Help", "does" => [ "money 30" ] }, { "label" => "Leave it", "does" => [] } ] } })
    at_the_table(campaign, as: "gm")
    expect(response.body).to include("Put it to the table")
    post message_saying_path(note)
    expect(campaign.reload.open_choice).to have_attributes(options: [ "Help", "Leave it" ], flag_key: "helped_cart")
  end

  it "lets the GM make a hard move so, and says what it takes on the facts page" do
    campaign.update!(gil: 100)
    note = campaign.narrate("A hard move, for the failed check: “A purse goes missing.”", scope: "gm",
                            data: { "offer" => { "text" => "A purse goes missing.", "does" => "lose 50" } })
    at_the_table(campaign, as: "gm")
    expect(response.body).to include("Make it so")
    post message_saying_path(note)
    expect(campaign.reload.gil).to eq(50)
    expect(campaign.messages.where(scope: "table").last(2).map(&:body)).to eq([ "A purse goes missing.", "The party loses 50 gil." ])

    get world_generation_facts_path(world)
    expect(response.body).to include("When a check fails", "lose 50", "difficulty")
  end
end
