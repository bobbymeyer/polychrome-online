# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe "Recurring antagonists" do
  let(:world) { Seeds::BaseWorld.run }
  let(:campaign) { world.campaigns.create!(name: "Pulp") }
  let(:hero) { campaign.characters.create!(name: "Rook", job: world.jobs.find_by!(slug: "knight"), starting_level: 10) }
  let(:gorn) { campaign.npcs.create!(name: "Gorn the Red", monster: world.monsters.find_by!(slug: "goblin_chief")) }

  def fight(**options)
    BattleRecord.start!(campaign: campaign, characters: [ hero ], name: "Alley", encounter: {}, antagonists: [ gorn ], seed: 3, **options)
  end

  def gm(battle, op, **params)
    battle.apply!({ "type" => "gm_override", "op" => op }.merge(params.transform_keys(&:to_s)), actor: "gm")
  end

  it "fights under their own name, as a boss, from their Bestiary entry" do
    battle = fight
    unit = battle.state["units"].find { |u| u["id"] == gorn.battle_unit_id }
    expect(unit).to include("name" => "Gorn the Red", "boss" => true, "image" => { "book" => "npcs", "slug" => gorn.id.to_s })
    expect(unit["stats"]).to eq(gorn.monster.stats)
    expect(battle).to be_boss
    expect(campaign.messages.first.body).to start_with("Alley begins: Rook against Gorn the Red.")
  end

  it "gets away when sent off the field, and comes back stronger" do
    battle = fight
    gm(battle, "dismiss", unit: gorn.battle_unit_id)
    expect(battle.reload.settlement["antagonists"]).to eq([ { "name" => "Gorn the Red", "fate" => "escaped" } ])
    expect(campaign.messages.last.body).to include("Gorn the Red got away, and will be back stronger.")
    expect(gorn.reload.escapes).to eq(1)

    again = fight
    unit = again.state["units"].find { |u| u["id"] == gorn.battle_unit_id }
    expect(unit["stats"]["str"]).to eq(gorn.monster.stats["str"] * 115 / 100)
    expect(Recap.new(campaign, 1.hour.ago..1.minute.from_now).battle_lines.first).to eq("Won: Alley (Gorn the Red got away)")
  end

  it "is finished when knocked out, and won't fight again" do
    battle = fight
    gm(battle, "set_hp", unit: gorn.battle_unit_id, value: 0)
    expect(battle.reload.settlement["antagonists"]).to eq([ { "name" => "Gorn the Red", "fate" => "defeated" } ])
    expect(gorn.reload).to be_defeated
    expect(campaign.npcs.at_large).to be_empty
    expect { fight }.to raise_error(Refusal, /defeated for good/)
  end

  it "must fight as one of the campaign world's monsters" do
    alien = World.create!(slug: "far", name: "Far").monsters.create!(name: "Thing", slug: "thing", stats: gorn.monster.stats, ai_script: [ { use: "attack" } ])
    npc = campaign.npcs.new(name: "X", monster: alien)
    expect(npc).not_to be_valid
  end
end
