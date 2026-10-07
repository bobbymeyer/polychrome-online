# frozen_string_literal: true

require "rails_helper"

RSpec.describe BattlesHelper, type: :helper do
  describe "the command help line" do
    let(:field) { BattleState.new(build_battle) }
    let(:vivi) { field.unit("vivi") }
    let(:fire) { field.ability("fire") }

    it "says what an ability hits, does and costs" do
      expect(helper.ability_help(vivi, fire)).to eq("Single enemy · Fire damage, power #{fire['effects'].first['power']} · #{Battle::State.ability_cost(fire)} MP")
    end

    it "says why an ability can't be used" do
      vivi.to_h["mp"] = 0
      expect(helper.ability_help(vivi, fire)).to eq("Not enough MP (needs #{Battle::State.ability_cost(fire)}, you have 0).")
      vivi.statuses << { "kind" => "silence", "turns" => 2 }
      expect(helper.ability_help(vivi, fire)).to start_with("Silenced")
    end

    it "warns when a move can't touch the target, from what's known" do
      goblin = field.unit("goblin_a") # normal type
      attack = field.ability("attack")
      vivi.to_h["attack_type"] = "ghost"
      expect(helper.futile_note(nil, field, vivi, attack, goblin)).to eq("Won't affect #{goblin.name}")
      vivi.to_h.delete("attack_type")
      expect(helper.futile_note(nil, field, vivi, attack, goblin)).to be_nil
      expect(helper.futile_note(nil, field, vivi, fire, goblin)).to be_nil

      goblin.to_h["affinities"] = { "fire" => "absorb" }
      expect(helper.futile_note(nil, field, vivi, fire, goblin)).to eq("#{goblin.name} absorbs it")
    end

    it "shows an ally's HP and MP but never an enemy's" do
      expect(helper.target_help(nil, field, "vivi")).to start_with("HP #{vivi.hp}/#{vivi.max_hp} · MP #{vivi.mp}")
      expect(helper.target_help(nil, field, "goblin_a")).to eq("Enemy · Normal type · Weak to Fire and Fighting · Immune to Ghost")
      expect(helper.target_help(nil, field, "goblin_a")).not_to include("HP")
    end

    it "tells what the Bestiary knows of an enemy: affinities and status immunities" do
      ogre = BattleState.new(build_battle(enemies: BattleFixtures.ogre))
      target = ogre.units.find(&:enemy?)
      expect(helper.target_help(nil, ogre, target.id)).to eq("Enemy · Normal type · Weak to Fighting · Resists Fire · Immune to Ghost and Sleep · Absorbs Ice")
    end
  end

  describe "a unit's picture" do
    let(:image) { Rack::Test::UploadedFile.new(file_fixture("goblin.png"), "image/png") }

    it "draws a party member as their own portrait, their job's art without one, and a lettered plate without either" do
      battle = start_battle
      bartz = battle.campaign.characters.find_by!(name: "Bartz")
      unit = battle.unit(bartz.battle_unit_id)
      expect(helper.unit_sprite(battle, unit)).to include("sprite__plate", ">B<")

      bartz.job.image.attach(image)
      helper.instance_variable_set(:@unit_art, nil)
      expect(helper.unit_sprite(battle, unit)).to include("sprite__image")

      bartz.update_portraits!(uploads: { "neutral" => Rack::Test::UploadedFile.new(file_fixture("goblin.png"), "image/png") })
      helper.instance_variable_set(:@unit_art, nil)
      expect(helper.unit_sprite(battle, unit)).to include("sprite__image", bartz.portraits.find_by!(expression: "neutral").image.blob.filename.to_s)
    end
  end
end
