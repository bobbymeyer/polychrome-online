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

  it "gives a villain fought from the Fight panel their card and line, and one met after a prelude their card alone" do
    rook = create_character(campaign, name: "Rook")
    morrow = campaign.npcs.find_by!(name: "Morrow")
    sign_in_as(@admin)
    sit(campaign, "gm")
    fight = BattleRecord.start!(campaign: campaign, characters: [ rook ], name: "Morrow", encounter: {}, antagonists: [ morrow ])
    get battle_path(fight)
    card = page.at(".boss-intro")
    expect(card["data-boss-intro-name-value"]).to eq("Morrow")
    expect(card["data-boss-intro-line-value"]).to eq(morrow.monster.boss_line)
    fight.call_off!

    campaign.update!(current_node: barrow)
    lair = barrow.location
    lair.enter!
    campaign.reload.wave_off_encounter!
    lair.reload
    lair.move_to!(lair.add_room!(name: "The Charter Vault", connect: lair.view["entrance"], decision: { "kind" => "boss", "monsters" => { "zombie" => 1 } }))
    met = campaign.reload.start_pending_encounter!
    expect(met).to be_prelude_said # the prelude said his line at the table
    get battle_path(met)
    expect(page.at(".boss-intro")["data-boss-intro-line-value"]).to be_blank # the name slams; the line isn't said twice
  end

  it "says the lair's master got away once the room is cleared, and names no rolled master beside the villain" do
    rook = create_character(campaign, name: "Rook")
    morrow = campaign.npcs.find_by!(name: "Morrow")
    campaign.update!(current_node: barrow)
    lair = barrow.location
    sign_in_as(@admin)
    sit(campaign, "gm")
    get location_path(lair)
    expect(page.text).not_to match(/who never came out\)\s*Morrow waits/) # the villain is who's there
    lair.resolve!(lair.view["boss"])
    morrow.update!(escapes: 1)
    get location_path(lair)
    expect(response.body).to include("(cleared)", "Morrow got away from here, #{morrow.strength_percent}% now, and is still about.")
    expect(rook).to be_present
  end

  it "names the villain in the GM's call, and weighs the odds with them in it" do
    create_character(campaign, name: "Rook")
    campaign.update!(current_node: barrow)
    lair = barrow.location
    lair.enter!
    campaign.reload.wave_off_encounter!
    lair.reload
    lair.move_to!(lair.add_room!(name: "The Charter Vault", connect: lair.view["entrance"], decision: { "kind" => "boss", "monsters" => { "goblin_chief" => 1, "goblin" => 2 } }))

    at_the_table(campaign, as: "gm")
    expect(response.body).to include("Morrow and 2 × Goblin", "Morrow, the Barrow Lord, turns to face you.")

    morrow = campaign.npcs.find_by!(name: "Morrow")
    get campaign_forecast_path(campaign, battle: { antagonists: [ morrow.id ] })
    expect(response.body).to match(/won \d+ of 20|lost|Fair|Easy|Hard|Deadly/)
  end
end
