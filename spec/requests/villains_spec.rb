# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A villain's boss room, at the table", type: :request do
  let(:campaign) { base_world.campaigns.create!(name: "The Barrow Road", gm: @admin).tap(&:set_out!) }
  let(:barrow) { campaign.map_nodes.find_by!(name: "The Old Barrow") }

  it "says in the lair's room list who waits at the head of it, and sizes up the bosses the GM can place" do
    create_character(campaign, name: "Rook")
    campaign.update!(current_node: barrow)
    sign_in_as(@admin)
    sit(campaign, "gm")
    get location_path(barrow.location)
    expect(response.body).to include("Morrow waits here, as Dark Mage, at the head of it.")
    expect(page.css("select#boss_monster option").map(&:text)).to include("Goblin Chief (#{base_world.monsters.find_by!(slug: 'goblin_chief').stats['max_hp']} HP, boss)")
  end

  it "names the villain in the GM's call, and weighs the odds with them in it" do
    create_character(campaign, name: "Rook")
    campaign.update!(current_node: barrow)
    lair = barrow.location
    lair.enter!
    lair.move_to!(lair.add_room!(name: "The Charter Vault", connect: lair.view["entrance"], decision: { "kind" => "boss", "monsters" => { "goblin_chief" => 1, "goblin" => 2 } }))

    at_the_table(campaign, as: "gm")
    expect(response.body).to include("Morrow and 2 × Goblin", "Morrow, the Barrow Lord, turns to face you.")

    morrow = campaign.npcs.find_by!(name: "Morrow")
    get campaign_forecast_path(campaign, battle: { antagonists: [ morrow.id ] })
    expect(response.body).to match(/won \d+ of 20|lost|Fair|Easy|Hard|Deadly/)
  end
end
