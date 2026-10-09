# frozen_string_literal: true

require "rails_helper"

# Duels and cowards at the table (Duel, Campaign::Duels, Character::Courage; docs/ODA.md).
RSpec.describe "Duels" do
  let(:campaign) { create_campaign }
  let(:world) { campaign.world }
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let!(:rival) { create_monster(world, slug: "ronin") }

  # Swing for a side at its grade this round: the centre of the target, or off it.
  def swing(duel, side, grade)
    zone = duel.zone
    off = { "perfect" => 0, "good" => DuelMeter::PERFECT + 1, "okay" => DuelMeter::PERFECT + zone["good"] + 1, "miss" => 200 }.fetch(grade)
    position = zone["center"] + off
    position = zone["center"] - off if position > DuelMeter::LENGTH
    duel.swing!(side, position.clamp(0, DuelMeter::LENGTH))
  end

  def play(duel, rounds)
    rounds.each do |mine, theirs|
      swing(duel, "character", mine)
      swing(duel.reload, "gm", theirs)
      duel.reload
    end
    duel
  end

  describe "the challenge" do
    it "waits on the table for the challenged character's answer" do
      campaign.challenge!(character: bartz, monster: rival, line: "Draw.")
      expect(campaign.reload.table_state).to eq("challenge")
      expect(campaign.challenged_character).to eq(bartz)
      expect(campaign.messages.last.body).to eq("Ronin challenges Bartz to a duel! “Draw.”")
    end

    it "starts a duel, outside battle, when they accept" do
      campaign.challenge!(character: bartz, monster: rival)
      duel = campaign.answer_challenge!(accept: true)
      expect(duel).to be_a(Duel).and(be_on)
      expect(duel.opponent_name).to eq("Ronin")
      expect(campaign.reload.table_state).to eq("duel")
      expect(campaign.battles).to be_empty
      expect(campaign.challenge).to be_nil
    end

    it "makes a coward of whoever refuses, with everything that costs" do
      town_price = ->(base) { Location.new(campaign: campaign).extend(Location::Town).price_here(base) }
      before = town_price.(100)
      bartz.job.update!(payoff: { "kind" => "money", "amount" => 10 })
      campaign.update!(spent_parts: 2)
      campaign.challenge!(character: bartz, monster: rival)
      campaign.answer_challenge!(accept: false)
      expect(bartz.reload).to be_coward
      expect(campaign.messages.last.body).to include("A coward has no place in this world.")
      expect(campaign.payoffs_owed.map(&:first)).not_to include(bartz)
      expect(town_price.(100)).to eq(before + Character::Courage::COWARD_PRICE)
      expect(bartz.battle_spec).to include("coward" => true)
    end

    it "lets the GM withdraw a challenge, shaming nobody" do
      campaign.challenge!(character: bartz, monster: rival)
      campaign.withdraw_challenge!
      expect(campaign.reload.challenge).to be_nil
      expect(bartz.reload).not_to be_coward
    end

    it "refuses a challenge while a battle or another duel is on, or with nobody to issue it" do
      expect { campaign.challenge!(character: bartz) }.to raise_error(Refusal)
      campaign.call_out!(character: bartz, monster: rival)
      expect { campaign.challenge!(character: bartz, monster: rival) }.to raise_error(Refusal, /duel is on/)
    end
  end

  describe "the duel" do
    let(:duel) { campaign.call_out!(character: bartz, monster: rival) }

    it "hides a swing until both are in, then shows the round to the table" do
      swing(duel, "character", "good")
      expect(duel.reload.shown_rounds).to be_empty
      expect(duel.swung?("character")).to be(true)
      expect(campaign.messages.last.body).not_to start_with("Round 1")
      expect { swing(duel, "character", "good") }.to raise_error(Refusal, /has swung/)
      swing(duel, "gm", "okay")
      expect(duel.reload.shown_rounds.size).to eq(1)
      expect(duel.round).to eq(2)
      expect(campaign.messages.last.body).to eq("Round 1: Bartz: good (2) · Ronin: okay (1).")
    end

    it "is won on the higher total after three rounds; the loser goes down" do
      play(duel, [ %w[perfect okay], %w[good good], %w[miss okay] ])
      expect(duel).to be_over
      expect(duel.result).to eq("character")
      expect(duel.totals).to eq("character" => 5, "gm" => 4)
      expect(campaign.messages.pluck(:body)).to include("Bartz wins the duel, 5 to 4. Ronin goes down.")

      other = create_character(campaign, name: "Faris")
      duel.close!
      lost = play(campaign.call_out!(character: other, monster: rival), [ %w[miss perfect], %w[okay good], %w[good good] ])
      expect(lost.result).to eq("gm")
      expect(other.reload).not_to be_conscious
    end

    it "reads SATISFACTION on level totals, and both win" do
      bartz.update!(coward: true)
      play(duel, [ %w[good okay], %w[okay good], %w[perfect perfect] ])
      expect(duel.result).to eq("satisfaction")
      expect(duel.result_line).to eq("SATISFACTION")
      expect(bartz.reload).not_to be_coward
      expect(bartz).to be_conscious
      expect(campaign.messages.pluck(:body).join).to include("SATISFACTION.")
    end

    it "takes a coward's shame away when they win" do
      bartz.update!(coward: true)
      play(duel, [ %w[perfect miss], %w[perfect miss], %w[perfect miss] ])
      expect(bartz.reload).not_to be_coward
    end

    it "takes no swings once it's over, and is put away by the GM" do
      play(duel, [ %w[good good], %w[good good], %w[good good] ])
      expect { duel.swing!("character", 10) }.to raise_error(Refusal, /over/)
      expect(campaign.reload.current_duel).to eq(duel)
      duel.close!
      expect(campaign.reload.current_duel).to be_nil
      expect(campaign.table_state).not_to eq("duel")
    end

    it "takes only a swing that stops on the meter" do
      expect { duel.swing!("character", 900) }.to raise_error(Refusal)
    end
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

  it "marks a monster as a giant" do
    expect(create_monster(world, slug: "oni", giant: true).to_engine).to include("giant" => true)
  end
end
