# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Location modes", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Pulp", gm: @admin) }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:town) { campaign.locations.create!(location_template: village, seed: 11) }
  let!(:node) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true, location: town) }
  let(:road) { campaign.map_nodes.create!(name: "Road", kind: "field", x: 300, y: 100, visible: true) }
  let(:hero) { campaign.characters.create!(name: "Rook", job: world.jobs.find_by!(slug: "knight"), starting_level: 10) }

  before { post campaign_table_seat_path(campaign), params: { seat: "gm" } }

  def prepare_burning
    post add_mode_location_path(town), params: { mode: { name: "Burning", line: "Smoke over the rooftops: Tule is burning.",
                                                         description: "Half the market is ash.", music: "battle",
                                                         encounters: "grasslands", closed: %w[shop inn] } }
  end

  it "prepares a mode, sets it off for the table, and puts it back" do
    prepare_burning
    expect(town.reload.modes.sole).to include("key" => "burning", "closed" => %w[shop inn], "music" => "battle")
    get location_path(town)
    expect(response.body).to include("GM: modes", "Burning", "Set it off")

    post switch_mode_location_path(town), params: { key: "burning" }
    expect(town.reload.current_mode["name"]).to eq("Burning")
    expect(campaign.messages.last.body).to eq("Smoke over the rooftops: Tule is burning.")
    get location_path(town)
    expect(response.body).to include("location-mode", "Half the market is ash.", "Shut: Shop and Inn")

    post clear_mode_location_path(town), params: { line: "The fires are out." }
    expect(town.reload.current_mode).to be_nil
    expect(campaign.messages.last.body).to eq("The fires are out.")
  end

  it "shuts its services, changes the music and has trouble waiting while it lasts" do
    prepare_burning
    town.reload.switch_mode!("burning")
    campaign.place_party!(node)
    expect(campaign.reload.scene).to eq("battle")
    expect { campaign.use_service!("inn", hero.tap { |h| h.update!(hp: 1) }, at: town, by: "Rook") }.to raise_error(Refusal, /shut: burning/)
    expect { campaign.buy!(world.items.find_by!(slug: "potion"), 1, at: town, by: "Rook") }.to raise_error(Refusal, /shop is shut/)

    campaign.place_party!(road)
    edge = campaign.map_edges.create!(from_node: road, to_node: node)
    campaign.reload.travel!(edge)
    expect(campaign.reload.pending_encounter).to include("table" => "Tule: Burning")
  end

  it "can be the ending of a scene" do
    prepare_burning
    post campaign_scenes_path(campaign), params: { scene: { name: "The raid", script: "Narrator: Torches in the dark.", ending: "mode",
                                                           mode_choice: "#{node.id}|burning" } }
    scene = campaign.scenes.last
    expect(scene).to have_attributes(ending: "mode", map_node_id: node.id, mode_key: "burning")
    expect(scene.summary).to include("then Tule: Burning")
    scene.play!
    expect(town.reload.current_mode["key"]).to eq("burning")
  end

  it "shows a in_mode place on the map" do
    prepare_burning
    town.reload.switch_mode!("burning")
    get campaign_map_path(campaign)
    expect(response.body).to include("has-mode", "map-node__mode")
  end
end
