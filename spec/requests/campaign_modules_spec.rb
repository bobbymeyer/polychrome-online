# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/campaigns/dead_calm")

RSpec.describe "Campaign modules", type: :request do
  before { World.where(slug: "oda").destroy_all }

  let(:bobby) { make_user("Bobby") }
  let!(:campaign) { Seeds::DeadCalm.run(gm: bobby) }

  def module_upload(zip)
    path = Rails.root.join("tmp", "module-#{SecureRandom.hex(4)}.zip")
    File.binwrite(path, zip)
    Rack::Test::UploadedFile.new(path, "application/zip")
  end

  it "lets the GM download the prep as a module, and nobody else" do
    sign_in_as(bobby)
    get campaign_prep_path(campaign)
    expect(response.body).to include("Export module")
    get campaign_campaign_module_path(campaign)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/zip")
    expect(response.headers["Content-Disposition"]).to include("dead-calm.module.zip")
    expect(CampaignModule::Archive.read(response.body).data["name"]).to eq("Dead Calm")

    sign_in_as(make_user("Stranger"))
    get campaign_campaign_module_path(campaign)
    expect(response).not_to have_http_status(:ok)
  end

  it "starts a campaign from an uploaded module, with whoever uploaded it as its GM" do
    zip = CampaignModule::Export.new(campaign).to_zip
    ines = sign_in_as(make_user("Ines"))
    get world_path(campaign.world)
    expect(response.body).to include("Import a module")
    get new_world_campaign_module_path(campaign.world)
    expect(response.body).to include("Module file")

    post world_campaign_modules_path(campaign.world), params: { module_file: module_upload(zip), name: "Dead Calm, Ines's table" }
    imported = Campaign.find_by!(name: "Dead Calm, Ines's table")
    expect(response).to redirect_to(campaign_prep_path(imported))
    expect(imported.gm).to eq(ines)
    expect(imported.scenes.count).to eq(campaign.scenes.count)
  end

  it "says why a module can't come in: not a module, or books only the world's editors can add" do
    sign_in_as(make_user("Ines"))
    post world_campaign_modules_path(campaign.world), params: { module_file: module_upload("not a zip") }
    expect(response).to redirect_to(new_world_campaign_module_path(campaign.world))
    expect(flash[:alert]).to include("isn't a campaign module")

    zip = CampaignModule::Export.new(campaign).to_zip
    World.where(slug: "oda").destroy_all
    world = Seeds::Oda.run # no Dead Calm in it, and Ines can't change its books
    post world_campaign_modules_path(world), params: { module_file: module_upload(zip) }
    expect(flash[:alert]).to include("only the world's editors can add them")
    expect(world.campaigns.count).to eq(0)
  end

  it "asks someone signed out to sign in first", :signed_out do
    get new_world_campaign_module_path(campaign.world)
    expect(response).to redirect_to(new_session_path)
  end
end
