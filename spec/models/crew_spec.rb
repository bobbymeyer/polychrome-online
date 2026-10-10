# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/campaigns/just_seven")

# The Giant Battle's crew: the party at Swirl-Pool's stations (Crew).
RSpec.describe Crew do
  before { World.where(slug: "oda").destroy_all }

  let(:gm) { User.create!(name: "Bobby", email_address: "crew-gm@example.com", password: "a-long-enough-password") }
  let!(:campaign) { Seeds::JustSeven.run(gm: gm) }
  let(:world) { campaign.world }
  let(:plan) { Seeds::JustSeven::CREW.deep_stringify_keys }

  def character(name, job, level: 13)
    campaign.characters.create!(name: name, job: world.jobs.find_by!(slug: job), starting_level: level)
  end

  def landfall(characters, seed: 3)
    BattleRecord.start!(campaign: campaign, characters: characters, name: "Landfall", encounter: { "fleet_crasher" => 1 }, seed: seed, crew: plan)
  end

  it "seats each character at the station their archetype fits, under their own name, and commanded as themselves" do
    party = [ character("Ana", "thief"), character("Bo", "healer"), character("Cy", "firemancer"), character("Di", "soldier") ]
    battle = landfall(party)
    units = battle.state["units"].select { |u| u["side"] == "party" }.index_by { |u| u["id"] }
    ana = units.fetch(party[0].battle_unit_id)
    expect(ana).to include("name" => "Ana · Rigging", "crewing" => "station_rigging", "types" => %w[dragon fairy])
    expect(ana["abilities"]).to include("grapple_line", "strip_the_plate", "cable_whip")
    expect(ana["stats"]["max_hp"]).to eq(800)
    expect(units.fetch(party[1].battle_unit_id)["crewing"]).to eq("station_damage_control")
    expect(units.fetch(party[2].battle_unit_id)["crewing"]).to eq("station_breath")
    expect(Battle::State.able_to_act(battle.state)).to match_array(party.map(&:battle_unit_id))

    # Four at the table: the cast's three wearers crew the rest, on their own.
    wearers = units.values.select { |u| u["guest"] }
    expect(wearers.map { |u| u["name"] }).to eq([ "The Swordsman · Blade", "Amethyst 7A · Ordnance", "The King · Damage Control" ])
    expect(wearers.map { |u| u["ai"] }).to all(be_present)
  end

  it "has each of fewer than four crew two stations, and the wearers fill what's left of the seven" do
    party = [ character("Ana", "thief"), character("Bo", "monk") ]
    battle = landfall(party)
    ana = battle.state["units"].find { |u| u["id"] == party[0].battle_unit_id }
    expect(ana["name"]).to start_with("Ana · Rigging & ")
    expect(ana["abilities"]).to include("grapple_line")
    expect(ana["abilities"].size).to be > 4
    expect(battle.state["units"].count { |u| u["guest"] }).to eq(3) # 2 × 2 worn, 3 to the cast: seven

    trio = landfall([ character("Cy", "magician"), character("Di", "ranger"), character("Ed", "courtsword") ])
    expect(trio.state["units"].count { |u| u["guest"] }).to eq(1) # 3 × 2 worn, 1 to the swordsman
  end

  it "leaves the characters' own HP alone when it's over: the damage was hers" do
    ana = character("Ana", "thief")
    battle = landfall([ ana ])
    battle.apply!({ "type" => "gm_override", "actor" => "gm", "op" => "set_hp", "unit" => ana.battle_unit_id, "value" => 1 }, actor: "gm")
    battle.apply!({ "type" => "gm_override", "actor" => "gm", "op" => "end_battle", "result" => "victory" }, actor: "gm")
    expect(ana.reload.hp).to be_nil.or(eq(ana.stats["max_hp"]))
    expect(battle.reload.settlement["result"]).to eq("victory")
  end

  it "fights the three phases of Fleet Crasher, weak where the notes say" do
    battle = landfall([ character("Ana", "thief") ])
    crasher = battle.state["units"].find { |u| u["side"] == "enemy" }
    expect(crasher).to include("name" => "Fleet Crasher", "giant" => true, "types" => %w[dragon fairy])
    expect(crasher["phases"].first["becomes"]["phases"].first["becomes"]["name"]).to eq("Fleet Crasher (Enraged)")
    %w[ice poison steel].each { |type| expect(Battle::Types.effectiveness(type, crasher, battle.state["types"])).to eq(200), type }
  end
end
