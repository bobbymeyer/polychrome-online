# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Antagonists at the table", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Pulp", gm: @admin) }
  let!(:hero) { campaign.characters.create!(name: "Rook", job: world.jobs.find_by!(slug: "knight"), starting_level: 10) }

  it "makes an NPC an antagonist, puts them in a battle, and shows them on the board" do
    post campaign_npcs_path(campaign), params: { npc: { name: "Gorn the Red", monster_id: world.monsters.find_by!(slug: "goblin_chief").id } }
    gorn = campaign.npcs.find_by!(name: "Gorn the Red")
    expect(gorn).to be_antagonist

    get new_campaign_battle_path(campaign)
    expect(response.body).to include("Antagonists", "Gorn the Red", "as Goblin Chief")

    post campaign_battles_path(campaign), params: { battle: { name: "Alley", characters: [ hero.id ], antagonists: [ gorn.id ],
                                                             encounter: { "0" => { monster: "", count: "1" } } } }
    battle = campaign.battles.last
    expect(battle.state["units"].map { |u| u["name"] }).to include("Gorn the Red")
    get battle_path(battle)
    expect(response.body).to include("Gorn the Red")
  end
end
