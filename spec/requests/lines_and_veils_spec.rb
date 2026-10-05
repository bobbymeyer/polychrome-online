# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A table's own lines and veils", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Pulp", gm: @admin) }
  let(:player) { make_user("Player") }
  let!(:rook) { create_character(campaign, name: "Rook", user: player) }

  before { world.update!(lines: "harm to children", veils: "torture") }

  it "lets a player draw one from their seat, with no name on it, beside the world's" do
    sign_in_as(player)
    post campaign_table_seat_path(campaign), params: { seat: rook.id }
    get campaign_table_path(campaign)
    expect(response.body).to include("Add one for this table")

    post campaign_limits_path(campaign), params: { kind: "line", text: "  spiders " }
    post campaign_limits_path(campaign), params: { kind: "veil", text: "drowning" }
    expect(campaign.reload).to have_attributes(lines: "spiders", veils: "drowning")
    expect(campaign.every_line).to eq([ "harm to children", "spiders" ])
    said = campaign.messages.where(kind: "system").pluck(:body)
    expect(said).to include("New for this table, never: spiders.", "New for this table, off-screen: drowning.")
    expect(said.join).not_to include("Rook", "Player")

    post campaign_limits_path(campaign), params: { kind: "line", text: "Spiders" }
    expect(flash[:notice]).to eq("That one is already there.")
    expect(campaign.reload.lines).to eq("spiders")

    get campaign_table_path(campaign) # read where they're drawn: the table (and the join page); not the campaign page
    expect(response.body).to include("harm to children<br>spiders", "torture<br>drowning")
    get campaign_path(campaign)
    expect(response.body).not_to include("Lines and veils")
    get join_path(campaign.join_code || campaign.new_join_code!)
    expect(response.body).to include("spiders", "drowning")
  end

  it "says no to anything but a line or a veil, an empty one, and anyone who doesn't play here" do
    post campaign_limits_path(campaign), params: { kind: "lines", text: "spiders" }
    expect(flash[:alert]).to eq("A line or a veil, nothing else.")
    post campaign_limits_path(campaign), params: { kind: "veil", text: " " }
    expect(flash[:alert]).to eq("Say what it is.")

    sign_in_as(make_user("Stranger"))
    post campaign_limits_path(campaign), params: { kind: "line", text: "spiders" }
    expect(response).to have_http_status(:forbidden)
    expect(campaign.reload.lines).to be_nil
  end

  it "lets only the GM take one off, on the campaign's edit page" do
    campaign.draw_limit!("line", "spiders")
    campaign.draw_limit!("line", "fire")
    sign_in_as(player)
    patch campaign_path(campaign), params: { campaign: { lines: "fire" } }
    expect(campaign.reload.lines).to eq("spiders\nfire")

    sign_in_as(@admin)
    get edit_campaign_path(campaign)
    expect(response.body).to include("This table's lines and veils")
    patch campaign_path(campaign), params: { campaign: { lines: "fire" } }
    expect(campaign.reload.lines).to eq("fire")
  end
end
