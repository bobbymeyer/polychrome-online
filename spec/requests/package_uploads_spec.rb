# frozen_string_literal: true

require "rails_helper"

RSpec.describe "An upload too big to be a package", type: :request do
  def too_big(format) = { "CONTENT_LENGTH" => (PackageArchive::KINDS.fetch(format)[:max_bytes] + 2.megabytes).to_s }

  it "is refused by its size, before anything reads it" do
    world = create_world
    sign_in_as(make_user("Mallory"))
    post world_import_path, params: { package_file: "x" }, env: too_big(WorldPackage::FORMAT)
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("too big to be a world")

    post world_campaign_modules_path(world), params: { module_file: "x" }, env: too_big(CampaignModule::FORMAT)
    expect(flash[:alert]).to include("too big to be a campaign module")
    expect(world.campaigns).to be_empty
  end
end
