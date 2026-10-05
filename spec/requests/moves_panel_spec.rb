# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The GM's moves panel (Campaign::Moves)", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Pulp", gm: @admin, gil: 100) }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let!(:tule) do
    campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true, location: campaign.locations.create!(location_template: village, seed: 11))
  end
  let!(:barrow) { campaign.map_nodes.create!(name: "The Barrow", kind: "dungeon", x: 300, y: 100, visible: true) }
  let(:player) { make_user("Player") }
  let!(:rook) { create_character(campaign, name: "Rook", user: player) }
  let(:remedy) { world.items.find_by!(slug: "remedy") }
  let(:folk) do
    [ { "key" => "npc-0", "name" => "Oskar", "title" => "Townsfolk", "wish" => "My father's fever won't break.", "wants" => "remedy" },
      { "key" => "npc-1", "name" => "Lenne", "title" => "Townsfolk", "wish" => "I'd give anything to see {dungeon} quiet again." },
      { "key" => "npc-2", "name" => "Dorn", "title" => "Townsfolk", "wish" => "I keep a lantern in the window." } ]
  end

  before do
    world.generator_tables.where(kind: "complications").destroy_all
    world.generator_tables.create!(name: "Moves", slug: "moves_spec", kind: "complications",
                                   entries: [ { "text" => "Somebody's watching {place}.", "when" => "town", "sets" => "watched" },
                                              { "text" => "A purse goes missing.", "does" => "lose 30" } ])
    campaign.map_edges.create!(from_node: tule, to_node: barrow)
    campaign.update!(current_node: tule)
    allow_any_instance_of(Location).to receive(:townsfolk).and_return(folk)
  end

  it "shows the GM what's live: a soft and a hard move, the dangers, wishes heard and who got away" do
    campaign.clocks.create!(name: "The goblins raid", segments: 4, filled: 2, impulse: "To bleed Tule dry",
                            portents: "Farms robbed.\n- A trampled hedge.\nThe mill burns.\n- Smoke at {place}. | town\nThe granary.")
    campaign.count_visit!(tule)
    campaign.npcs.create!(name: "Grol Tusk", monster: world.monsters.first, escapes: 1, location: tule.location)
    campaign.npcs.create!(name: "Never met", monster: world.monsters.first)

    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    campaign.call_controls!("tools") # GM tools is a control on the strip
    get campaign_table_path(campaign)
    expect(response.body).to include("gm_moves", "Moves")

    get campaign_moves_path(campaign)
    page = Nokogiri::HTML(response.body).at("turbo-frame#gm_moves").text.squish
    expect(page).to include("“Somebody's watching Tule.” Say it", "“A purse goes missing.” (The party loses 30 gil) Make it so")
    expect(page).to include("The goblins raid (2 of 4) Wants to bleed Tule dry. Next: The granary. A sign: “Smoke at Tule.” Show it Tick it")
    expect(page).to include("Oskar of Tule: “My father's fever won't break.” (Remedy)", "Lenne of Tule: “I'd give anything to see The Barrow quiet again.” (The Barrow)")
    expect(page).not_to include("Dorn", "Never met")
    expect(page).to include("Grol Tusk (1 time, 115% now) · at Tule")

    secret = campaign.secrets.create!(body: "The reeve sold the mill.", steps: "Who owns the mill?\nThe mill's ledger is in a stranger's hand.")
    get campaign_moves_path(campaign)
    expect(Nokogiri::HTML(response.body).at("turbo-frame#gm_moves").text.squish).to include("Chains Who owns the mill? (0 of 2 found) Next: Who owns the mill? Let them find it")
    post campaign_secret_clues_path(campaign, secret)
    expect(secret.reload.found).to eq(1)

    patch campaign_secret_path(campaign, secret), params: { secret: { key: "Mill Owner", steps: "Who owns the mill?\nA new clue." } }
    expect(secret.reload).to have_attributes(key: "mill_owner", steps: "Who owns the mill?\nA new clue.")
    get campaign_prep_path(campaign)
    expect(response.body).to include("1 of 2 clues found · key mill_owner · next: A new clue.")
  end

  it "makes a move so: its words to the table, what it remembers, and what a hard one takes" do
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    post campaign_moves_path(campaign), params: { move: { text: "Somebody's watching Tule.", sets: "watched, sightings + 1" } }
    expect(response).to redirect_to(campaign_moves_path(campaign))
    post campaign_moves_path(campaign), params: { move: { text: "A purse goes missing.", sets: "", does: "lose 30" } }
    expect(campaign.messages.where(scope: "table").pluck(:body)).to eq([ "Somebody's watching Tule.", "A purse goes missing.", "The party loses 30 gil." ])
    expect(campaign.flags.pluck(:key, :value)).to contain_exactly([ "watched", "yes" ], [ "sightings", "1" ])
    expect(campaign.reload.gil).to eq(70)

    post campaign_moves_path(campaign), params: { move: { text: "Lucky!", does: "money 500" } }
    expect(flash[:alert]).to eq("“money 500” isn't something a hard move takes")
    expect(campaign.reload.gil).to eq(70)
  end

  it "is the GM's alone" do
    sign_in_as(player)
    get campaign_moves_path(campaign)
    expect(response).to have_http_status(:forbidden)
    post campaign_moves_path(campaign), params: { move: { text: "Hi." } }
    expect(response).to have_http_status(:forbidden)
  end
end
