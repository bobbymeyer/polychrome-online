# frozen_string_literal: true

require "rails_helper"

RSpec.describe BattlesHelper, type: :helper do
  describe "the command help line" do
    let(:state) { build_battle }
    let(:vivi) { unit(state, "vivi") }
    let(:fire) { state["abilities"]["fire"] }

    it "says what an ability hits, does and costs" do
      expect(helper.ability_help(vivi, fire)).to eq("Single enemy · Fire damage, power #{fire['effects'].first['power']} · #{Battle::State.ability_cost(fire)} MP")
    end

    it "says why an ability can't be used" do
      vivi["mp"] = 0
      expect(helper.ability_help(vivi, fire)).to eq("Not enough MP (needs #{Battle::State.ability_cost(fire)}, you have 0).")
      vivi["statuses"] << { "kind" => "silence", "turns" => 2 }
      expect(helper.ability_help(vivi, fire)).to start_with("Silenced")
    end

    it "shows an ally's HP and MP but never an enemy's" do
      expect(helper.target_help(nil, state, "vivi")).to start_with("HP #{vivi['hp']}/#{vivi['stats']['max_hp']} · MP #{vivi['mp']}")
      expect(helper.target_help(nil, state, "goblin_a")).to eq("Enemy · Normal type · Weak to Fire and Fighting · Immune to Ghost")
      expect(helper.target_help(nil, state, "goblin_a")).not_to include("HP")
    end

    it "tells what the Bestiary knows of an enemy: affinities and status immunities" do
      ogre = build_battle(enemies: BattleFixtures.ogre)
      target = ogre["units"].find { |u| u["side"] == "enemy" }
      expect(helper.target_help(nil, ogre, target["id"])).to eq("Enemy · Normal type · Weak to Fighting · Resists Fire · Immune to Ghost and Sleep · Absorbs Ice")
    end
  end
end
