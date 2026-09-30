# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A world's battle rules", type: :request do
  let(:world) { World.create!(name: "Undertow", slug: "undertow_rules", owner: @admin).tap { |w| w.copy_books_from!(base_world, rules_only: true) } }

  it "turns One More on from the world's form, and every battle there plays it; copies keep it" do
    get edit_world_path(world)
    expect(response.body).to include("Battle rules", "One More")

    patch world_path(world), params: { world: { name: world.name, battle_rules: { one_more: "1" } } }
    expect(world.reload.battle_rules).to eq("one_more" => true)
    campaign = world.campaigns.create!(name: "Spring Term", gm: @admin)
    battle = start_battle(campaign: campaign)
    expect(battle.state["rules"]).to eq("one_more" => true)

    copy = World.create!(name: "Second Term", slug: "second_term", owner: @admin)
    copy.copy_books_from!(world, rules_only: true)
    expect(copy.rule?(:one_more)).to be(true)

    patch world_path(world), params: { world: { name: world.name, battle_rules: { one_more: "0" } } }
    expect(world.reload.battle_rules).to eq({})
    expect(base_world.battle(seed: 1, party: [], monsters: { "goblin" => 1 })).not_to have_key("rules")
  end
end
