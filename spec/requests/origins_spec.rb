# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe "Where characters come from", type: :request do
  let!(:world) { Seeds::BaseWorld.run }
  let(:campaign) { world.campaigns.create!(name: "Rust", gm: @admin) }
  let!(:varn) { campaign.map_nodes.create!(name: "Varn", kind: "town", x: 1, y: 1, visible: true) }
  let!(:mara) { campaign.npcs.create!(name: "Mara Vell") }
  let(:stealth) { world.skills.first["slug"] }

  before do
    patch world_origins_path(world), params: { origins: { "0" => { name: "Dockborn", skill: stealth, description: "Raised on the wharves." }, "1" => { name: "" } } }
  end

  it "keeps a world's origins, each maybe better at a skill" do
    expect(world.reload.origins).to eq([ { "slug" => "dockborn", "name" => "Dockborn", "skill" => stealth, "description" => "Raised on the wharves." } ])
    get world_origins_path(world)
    expect(response.body).to include("Dockborn", "Raised on the wharves.")
    patch world_origins_path(world), params: { origins: { "0" => { name: "Odd", skill: "juggling" } } }
    expect(response.body).to include("juggling isn&#39;t one of the skills")
  end

  it "gives a character an origin, a home and ties, and the origin's skill a bonus" do
    post campaign_characters_path(campaign), params: { character: {
      name: "Rook", job_id: world.jobs.find_by!(slug: "knight").id, starting_level: 5, origin: "dockborn", home_node_id: varn.id,
      ties: { "0" => { npc_id: mara.id, text: "owes her money" }, "1" => { npc_id: "", text: "" } }
    } }
    world.reload
    rook = campaign.characters.find_by!(name: "Rook")
    expect(rook).to have_attributes(origin: "dockborn", home_node: varn, ties: [ { "npc_id" => mara.id, "text" => "owes her money" } ])
    expect(rook.skill_bonus(stealth)).to eq(World::ORIGIN_BONUS + (rook.job.skills.include?(stealth) ? Job::SKILL_BONUS : 0))

    get character_path(rook)
    expect(response.body).to include("Dockborn, home in Varn.", "Mara Vell: owes her money")
    draft = Draft.new(owner: campaign, kind: "secrets", request: {})
    expect(draft.writer.messages[:user]).to include("- Rook, Knight, Dockborn, home in Varn; ties: Mara Vell: owes her money")

    patch character_path(rook), params: { character: { origin: "nowhere" } }
    expect(response.body).to include("isn&#39;t one of")
  end
end
