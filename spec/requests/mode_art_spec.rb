# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pictures for location modes (§8)", type: :request do
  let!(:world) { base_world }
  let(:campaign) { base_campaign(name: "Pulp", gm: @admin) }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:town) { campaign.locations.create!(location_template: village, seed: 11) }
  let!(:node) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true, location: town) }

  before do
    sit(campaign, "gm")
    post map_node_modes_path(town.map_node), params: { mode: { name: "Burning" } }
  end

  it "takes an uploaded picture for a mode, and shows it while the mode lasts" do
    get location_path(town)
    expect(response.body).to include("Pictures for modes", "No picture")
    expect(response.body).not_to include("location-picture")
    expect(response.body.index("Pictures for modes")).to be > response.body.index("Services") # the town first

    patch location_mode_art_path(town, "burning"), params: { mode_art: { image: fixture_file_upload("goblin.png", "image/png") } }
    expect(response).to redirect_to(location_path(town, anchor: "mode-pictures"))
    art = town.mode_arts.sole
    expect(art.image).to be_attached

    get location_path(town)
    expect(response.body).not_to include("location-picture") # not burning yet
    town.map_node.reload.switch_mode!("burning")
    get location_path(town)
    expect(response.body).to include("location-picture is-mode")
    expect(town.picture.blob).to eq(art.image.blob)

    delete location_mode_art_path(town, "burning")
    expect(town.reload.mode_arts).to be_empty
    expect(town.picture&.blob).not_to eq(art.image.blob)

    patch location_mode_art_path(town, "burning"), params: { mode_art: { image: fixture_file_upload("goblin.png", "image/png") } }
    delete map_node_mode_path(town.map_node, "burning")
    expect(town.reload.mode_arts).to be_empty
  end

  it "is the GM's to upload" do
    sign_in_as(make_user("Player"))
    patch location_mode_art_path(town, "burning"), params: { mode_art: { image: fixture_file_upload("goblin.png", "image/png") } }
    expect(town.mode_arts).to be_empty
  end
end
