# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pictures for location modes (§8)", type: :request do
  include ActiveJob::TestHelper

  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Pulp", gm: @admin) }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:town) { campaign.locations.create!(location_template: village, seed: 11) }
  let!(:node) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true, location: town) }
  let(:comfy) { FakeComfy.new }

  before do
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    post map_node_modes_path(town.map_node), params: { mode: { name: "Burning", art: "on fire, thick smoke" } }
  end

  def finish(batch)
    ArtBatchJob.new.perform(batch.reload, client: comfy)
    comfy.finish!(*comfy.submitted.each_index.map { |i| "prompt-#{i + 1}" })
    ArtBatchJob.new.perform(batch.reload, client: comfy)
  end

  it "draws the place as it is in the mode, and shows that picture while the mode lasts" do
    expect(town.reload.modes.sole["art"]).to eq("on fire, thick smoke")
    village.update!(image_seed: 4242)
    get location_path(town)
    expect(response.body).to include("Pictures for modes", "on fire, thick smoke")
    expect(response.body).not_to include("location-picture")

    post world_art_batches_path(world), params: { entry_type: "location_mode", location_id: town.id, mode: "burning",
                                                  mode_art: "on fire, thick smoke, ash falling", count: 2 }
    expect(response).to redirect_to(location_path(town, anchor: "art"))
    art = town.mode_arts.sole
    batch = art.art_batch
    expect(batch.recipe["positive"]).to end_with("#{village.art_subject}, on fire, thick smoke, ash falling")
    expect(batch.candidates.first.seed).to eq(4242)
    expect(town.reload.modes.sole["art"]).to eq("on fire, thick smoke, ash falling")

    finish(batch)
    post world_art_candidate_pick_path(world, batch.candidates.first)
    expect(response).to redirect_to(location_path(town, anchor: "art"))
    expect(art.reload.image).to be_attached

    get location_path(town)
    expect(response.body).not_to include("location-picture") # not burning yet
    town.reload.switch_mode!("burning")
    get location_path(town)
    expect(response.body).to include("location-picture is-mode")
    expect(town.picture.blob).to eq(art.image.blob)

    delete map_node_mode_path(town.map_node, "burning")
    expect(town.reload.mode_arts).to be_empty
  end

  it "is the GM's to make" do
    sign_in_as(make_user("Player"))
    post world_art_batches_path(world), params: { entry_type: "location_mode", location_id: town.id, mode: "burning" }
    expect(town.mode_arts.filter_map(&:art_batch)).to be_empty
  end
end
