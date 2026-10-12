# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Baible skeletons", type: :request do
  let!(:world) { base_world }
  let(:gm) { make_user("Bobby") }
  let(:campaign) { base_campaign(gm: gm) }

  it "lets the GM download the campaign's art needs for baible, from Prep, and nobody else" do
    campaign.npcs.create!(name: "Cid")
    sign_in_as(gm)
    get campaign_prep_path(campaign)
    expect(response.body).to include("Export for baible")

    get campaign_baible_skeleton_path(campaign)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Content-Disposition"]).to include("crystal-road.baible.json")
    data = JSON.parse(response.body)
    expect(data).to include("baible_skeleton" => 1, "project" => include("name" => "Crystal Road"))
    expect(data["assets"].map { |a| a["name"] }).to include("Cid", "Cid, portrait", "Cid, sprite")

    sign_in_as(make_user("Stranger"))
    get campaign_baible_skeleton_path(campaign)
    expect(response).not_to have_http_status(:ok)
  end
end
