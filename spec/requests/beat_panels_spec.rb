# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Panels for a scene's beats (§8)", type: :request do
  include ActiveJob::TestHelper

  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Pulp", gm: @admin) }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:town) { campaign.locations.create!(location_template: village, seed: 11) }
  let!(:node) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true, location: town) }
  let(:scene) { campaign.scenes.create!(name: "The quay", script: "Narrator: The fog lifts off the harbour.\nNarrator: A sail.") }
  let(:comfy) { FakeComfy.new }

  before { post campaign_table_seat_path(campaign), params: { seat: "gm" } }

  def finish(batch)
    ArtBatchJob.new.perform(batch.reload, client: comfy)
    comfy.finish!(*comfy.submitted.each_index.map { |i| "prompt-#{i + 1}" })
    ArtBatchJob.new.perform(batch.reload, client: comfy)
  end

  it "draws the beat as the place it stands in with the beat's words added, and shows the panel on the stage" do
    village.update!(image_seed: 4242)
    first, second = scene.beats.to_a
    first.update!(backdrop: "place", map_node: node)
    second.update!(backdrop: "panel")

    get edit_scene_path(scene, beat: second.id)
    expect(response.body).to include("Panel for beat 2", "Village's own picture with this beat's words added")

    post world_art_batches_path(world), params: { entry_type: "beat", beat_id: second.id, beat_words: "a black sail on the horizon", count: 2 }
    expect(response).to redirect_to(edit_scene_path(scene, beat: second.id, anchor: "art"))
    batch = second.reload.art_batch
    expect(batch.recipe["positive"]).to end_with("#{village.art_subject}, a black sail on the horizon")
    expect(batch.recipe["width"]).to be > batch.recipe["height"]
    expect(batch.candidates.first.seed).to eq(4242)
    expect(second.art_notes).to eq("a black sail on the horizon")

    finish(batch)
    post world_art_candidate_pick_path(world, batch.candidates.first)
    expect(response).to redirect_to(edit_scene_path(scene, beat: second.id, anchor: "art"))
    expect(second.reload.image).to be_attached

    scene.start!
    scene.advance!
    get campaign_table_path(campaign)
    expect(response.body).to include('class="table-scene is-scene"', "beat-stage--panel", "beat-stage__backdrop")

    scene.destroy!
    expect(ArtBatch.where(id: batch.id)).to be_empty
  end

  it "is the GM's to make" do
    sign_in_as(make_user("Player"))
    post world_art_batches_path(world), params: { entry_type: "beat", beat_id: scene.beats.first.id }
    expect(scene.beats.filter_map(&:art_batch)).to be_empty
  end
end
