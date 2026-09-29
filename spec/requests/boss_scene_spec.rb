# frozen_string_literal: true

require "rails_helper"

# A dungeon's boss as a scene: words before the fight, and a fanfare after.
RSpec.describe "The boss and the victory", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road", gm: @admin) }
  let!(:bartz) { create_character(campaign, name: "Bartz", job: world.jobs.find_by!(slug: "knight")) }
  let(:cave_node) { campaign.map_nodes.create!(name: "Goblin Hollow", kind: "dungeon", x: 300, y: 300, visible: true) }
  let(:cave) do
    post map_node_location_path(cave_node), params: { location_template_id: world.location_templates.find_by!(slug: "goblin_cave").id }
    cave_node.reload.location
  end

  def walk_in_on_the_boss
    campaign.update!(current_node: cave_node)
    cave.enter!
    cave.send(:announce, cave.room(cave.view["boss"]))
    campaign.reload
  end

  it "offers the GM words for the boss's entrance, says them, then starts the fight" do
    walk_in_on_the_boss
    prelude = campaign.pending_encounter["prelude"]
    boss_room = cave.room(cave.view["boss"])
    expect(prelude.first).to start_with("#{boss_room['name']}.")
    expect(prelude.join(" ")).to include("turns to face you")

    get location_path(cave)
    expect(response.body).to include("Before the fight", ERB::Util.html_escape(prelude.first))

    post campaign_encounter_path(campaign), params: { prelude: "The torches gutter.\n\nA voice: “Mine.”", input_seconds: "" }
    battle = campaign.battles.last
    expect(response).to redirect_to(battle_path(battle))
    said = campaign.messages.where("id < ?", campaign.messages.find_by!(battle: battle).id).last(2)
    expect(said.map(&:body)).to eq([ "The torches gutter.", "A voice: “Mine.”" ])
    expect(said).to all(be_dialogue)
  end

  it "cheers a cleared dungeon at the table and stops the clocks it was behind" do
    raid = campaign.clocks.create!(name: "The goblins raid Tule", segments: 4, public: true, map_node: cave_node, triggers: %w[dawn])
    elsewhere = campaign.clocks.create!(name: "The mill burns", segments: 4)
    walk_in_on_the_boss
    battle = campaign.start_pending_encounter!
    battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")

    cleared = campaign.messages.find_by!(body: "Goblin Hollow is cleared!")
    expect(cleared.cue).to eq("cleared")
    expect(raid.reload).to be_stopped
    expect(campaign.messages.pluck(:body)).to include("The goblins raid Tule: not any more.")
    expect(elsewhere.reload).not_to be_stopped
    expect { raid.tick! }.not_to(change { raid.reload.filled })
    expect(campaign.clocks.running).to eq([ elsewhere ])
  end
end
