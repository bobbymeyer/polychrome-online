# frozen_string_literal: true

require "rails_helper"

# Duels and cowards at the table (Campaign::Duels, Character::Courage; docs/ODA.md).
RSpec.describe "Duels" do
  let(:campaign) { create_campaign }
  let(:world) { campaign.world }
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let!(:rival) { create_monster(world, slug: "ronin", technique: "tie_win", tells: { "strike" => "Now.\nEnough." }) }

  it "waits on the table for the challenged character's answer" do
    campaign.challenge!(character: bartz, monster: rival, line: "Draw.")
    expect(campaign.reload.table_state).to eq("challenge")
    expect(campaign.challenged_character).to eq(bartz)
    expect(campaign.challenger_name).to eq("Ronin")
    expect(campaign.messages.last.body).to eq("Ronin challenges Bartz to a duel! “Draw.”")
  end

  it "starts a duel when they accept: one against one, in stances, nobody running" do
    campaign.challenge!(character: bartz, monster: rival)
    battle = campaign.answer_challenge!(accept: true)
    expect(battle).to be_duel
    expect(battle.state).to include("kind" => "duel", "escapable" => false)
    expect(battle.party.map { |u| u["id"] }).to eq([ bartz.battle_unit_id ])
    expect(battle.enemies.map { |u| u["technique"] }).to eq([ "tie_win" ])
    expect(battle.enemies.first["tells"]).to eq("strike" => [ "Now.", "Enough." ])
    expect(campaign.reload.challenge).to be_nil
  end

  it "makes a coward of whoever refuses, with everything that costs" do
    town_price = ->(base) { Location.new(campaign: campaign).extend(Location::Town).price_here(base) }
    before = town_price.(100)
    bartz.job.update!(payoff: { "kind" => "money", "amount" => 10 })
    campaign.update!(spent_parts: 2)
    expect(campaign.payoffs_owed.map(&:first)).to include(bartz)

    campaign.challenge!(character: bartz, monster: rival)
    campaign.answer_challenge!(accept: false)
    expect(bartz.reload).to be_coward
    expect(campaign.messages.last.body).to include("A coward has no place in this world.")
    expect(campaign.payoffs_owed.map(&:first)).not_to include(bartz)
    expect(town_price.(100)).to eq(before + Character::Courage::COWARD_PRICE)
    expect(bartz.battle_spec).to include("coward" => true)
  end

  it "takes the shame away when they win a duel" do
    bartz.update!(coward: true)
    battle = campaign.call_out!(character: bartz, monster: rival)
    battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
    expect(bartz.reload).not_to be_coward
    expect(campaign.messages.last(3).map(&:body)).to include(a_string_including("Nobody calls them a coward now"))
  end

  it "lets the GM withdraw a challenge, shaming nobody" do
    campaign.challenge!(character: bartz, monster: rival)
    campaign.withdraw_challenge!
    expect(campaign.reload.challenge).to be_nil
    expect(bartz.reload).not_to be_coward
  end

  it "refuses a challenge while a battle is on, or with nobody to issue it" do
    expect { campaign.challenge!(character: bartz) }.to raise_error(Refusal)
    start_battle(campaign: campaign)
    expect { campaign.challenge!(character: bartz, monster: rival) }.to raise_error(Refusal, /battle is on/)
  end
end

RSpec.describe "Masks in the Armory" do
  let(:world) { create_world }
  let!(:raijin) { create_ability(world, slug: "raijin", kind: "skill", target: "all_enemies", effects: [ { primitive: "physical", power: 120, type: "electric" } ]) }

  it "is a mask: a type, how long it lasts, its moves, and a Don for whoever wears it" do
    mask = world.items.create!(slug: "storm_mask", name: "Storm Mask", category: "mask", mask: { type: "electric", duration: "3", abilities: [ "raijin", "" ] })
    expect(mask.mask).to eq("type" => "electric", "duration" => 3, "abilities" => [ "raijin" ])
    expect(world.mask_library["storm_mask"]).to include("name" => "Storm Mask", "type" => "electric", "abilities" => [ "raijin" ])
    expect(world.ability_library["don_storm_mask"]["effects"]).to eq([ { "primitive" => "transform", "mask" => "storm_mask" } ])
    expect(create_job(world, equip_categories: []).equips?(mask)).to be(true)
  end

  it "checks the mask's type, turns and moves" do
    mask = world.items.new(slug: "odd", name: "Odd", category: "mask", mask: { type: "plasma", duration: 9, abilities: [ "nothing" ] })
    expect(mask).not_to be_valid
    expect(mask.errors[:mask].join).to include("type", "1 to 5", "nothing")
    expect(world.items.new(slug: "sword2", name: "S", category: "sword", mask: { type: "fire" })).not_to be_valid
  end
end

RSpec.describe "A mask worn" do
  it "puts the Don on the menu of whoever wears it, and the mask in the battle" do
    campaign = create_campaign(world: knight_world)
    world = campaign.world
    create_ability(world, slug: "raijin", kind: "skill", target: "all_enemies", effects: [ { primitive: "physical", power: 120 } ])
    mask = world.items.create!(slug: "storm_mask", name: "Storm Mask", category: "mask", mask: { abilities: [ "raijin" ] })
    bartz = create_character(campaign)
    bartz.carry_row(mask).update!(quantity: 1)
    bartz.equip!(mask)
    expect(bartz.battle_spec["abilities"]).to include("don_storm_mask")
    battle = start_battle(campaign: campaign)
    expect(battle.state["masks"].keys).to eq([ "storm_mask" ])
  end
end

RSpec.describe "Oda's books" do
  let(:world) { create_world }

  it "gives a move its reload and reach" do
    shot = create_ability(world, slug: "long_shot", kind: "skill", reload_turns: 1, reach: true, effects: [ { primitive: "physical", power: 150 } ])
    expect(shot.to_engine).to include("reload" => 1, "reach" => true)
    expect(world.abilities.new(slug: "x", name: "X", kind: "skill", target: "self", reload_turns: 9, effects: [ { primitive: "scan" } ])).not_to be_valid
  end

  it "gives a monster its giant, technique and tells, and a job its technique" do
    oni = create_monster(world, slug: "oni", giant: true, technique: "read", tells: { "guard" => "Come, then.", "dance" => "x" })
    expect(oni.to_engine).to include("giant" => true, "technique" => "read", "tells" => { "guard" => [ "Come, then." ] })
    expect(world.monsters.new(slug: "y", name: "Y", stats: monster_stats, technique: "flail")).not_to be_valid
    expect(create_job(world, technique: "wait").technique).to eq("wait")
    expect(world.jobs.new(slug: "z", name: "Z", technique: "flail")).not_to be_valid
  end
end
