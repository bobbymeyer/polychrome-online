# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Panels for a scene's beats (§8)", type: :request do
  let!(:world) { base_world }
  let(:campaign) { base_campaign(name: "Pulp", gm: @admin) }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:town) { campaign.locations.create!(location_template: village, seed: 11) }
  let!(:node) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true, location: town) }
  let(:scene) { campaign.scenes.create!(name: "The quay", script: "Narrator: The fog lifts off the harbour.\nNarrator: A sail.") }

  before { sit(campaign, "gm") }

  it "takes an uploaded panel on a backdrop step, keeps it through other changes, and shows it on the stage" do
    place = scene.beats.create!(kind: "backdrop", backdrop: "place", map_node: node, position: 0)
    second = scene.beats.create!(kind: "backdrop", backdrop: "panel", position: 2)
    scene.beats.reload.each { |s| s.update_columns(position: [ place, scene.beats.find_by(text: "The fog lifts off the harbour."), second, scene.beats.find_by(text: "A sail.") ].index(s)) }

    get edit_scene_path(scene, beat: second.id)
    expect(response.body).to include("No panel yet: upload one")

    patch beat_path(second), params: { beat: { backdrop: "panel", image: fixture_file_upload("goblin.png", "image/png") } }
    expect(response).to redirect_to(edit_scene_path(scene, beat: second.id, anchor: "beat_#{second.id}"))
    expect(second.reload.image).to be_attached
    blob = second.image.blob

    patch beat_path(second), params: { beat: { backdrop: "panel", transition: "slow" } } # no file: the panel stays
    expect(second.reload).to have_attributes(transition: "slow")
    expect(second.image.blob).to eq(blob)

    scene.reload.start!
    scene.advance! # to the last line, past the panel
    expect(scene.reload.cursor).to eq(3)
    get campaign_table_path(campaign)
    expect(page.at(".table-scene.is-scene")).to be_present
    expect(page.at(".beat-stage--panel .beat-stage__backdrop")).to be_present
  end

  it "is the GM's to upload" do
    beat = scene.beats.create!(kind: "backdrop", backdrop: "panel", position: 2)
    sign_in_as(make_user("Player"))
    patch beat_path(beat), params: { beat: { backdrop: "panel", image: fixture_file_upload("goblin.png", "image/png") } }
    expect(beat.reload.image).not_to be_attached
  end
end
