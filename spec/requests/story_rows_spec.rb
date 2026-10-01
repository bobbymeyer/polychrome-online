# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Story rows: arrival lines, the facts page and the moment", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Pulp", gm: @admin) }
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
    expect(response).to have_http_status(:forbidden)

    sign_in_as(@admin)
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    get campaign_table_path(campaign)
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

  it "lets the GM make a hard move so, and says what it takes on the facts page" do
    campaign.update!(gil: 100)
    note = campaign.narrate("A hard move, for the failed check: “A purse goes missing.”", scope: "gm",
                            data: { "offer" => { "text" => "A purse goes missing.", "does" => "lose 50" } })
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    get campaign_table_path(campaign)
    expect(response.body).to include("Make it so")
    post message_saying_path(note)
    expect(campaign.reload.gil).to eq(50)
    expect(campaign.messages.where(scope: "table").last(2).map(&:body)).to eq([ "A purse goes missing.", "The party loses 50 gil." ])

    get world_generation_facts_path(world)
    expect(response.body).to include("When a check fails", "lose 50", "difficulty")
  end
end
