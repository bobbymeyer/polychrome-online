# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A setting's own words (Vocabulary)", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Rust", gm: @admin, gil: 500) }
  let(:village) { world.location_templates.find_by!(slug: "village") }

  def set_words
    patch world_path(world), params: { world: { name: world.name, voice: "Wet noir.",
                                                terms: { currency: "crowns", hp: "Grit", mp: "Nerve", stats: { str: "Brawn", mag: "" },
                                                         services: { temple: "Surgeon" }, statuses: { poison: "Rust-lock" },
                                                         services_off: [ "guild" ] } } }
    world.reload
  end

  it "keeps the setting's words, dropping blanks so the game's come back" do
    set_words
    expect(world.terms).to eq("currency" => "crowns", "hp" => "Grit", "mp" => "Nerve", "stats" => { "str" => "Brawn" },
                              "services" => { "temple" => "Surgeon" }, "statuses" => { "poison" => "Rust-lock" }, "services_off" => [ "guild" ])
    expect([ world.word("currency"), world.word("stat.str"), world.word("stat.mag"), world.word("status.poison"), world.word("status.sleep") ])
      .to eq([ "crowns", "Brawn", "Mag", "Rust-lock", "Sleep" ])
    expect(world.voice).to eq("Wet noir.")
  end

  it "uses them at the table and in towns, and leaves out services the setting doesn't have" do
    set_words
    hero = campaign.characters.create!(name: "Rook", job: world.jobs.find_by!(slug: "knight"), starting_level: 5)
    get campaign_path(campaign)
    expect(response.body).to include("500 crowns", "Grit #{hero.current_hp}", "Nerve")
    campaign.sleep!
    expect(campaign.messages.where("body LIKE ?", "The party rests. Everyone is back to full Grit, and half their Nerve.%")).to exist

    towns = Array.new(12) { |i| campaign.locations.create!(location_template: village, seed: i + 1) }
    expect(towns.flat_map { |t| t.view["services"].map { |s| s["kind"] } }).not_to include("guild")
    town = towns.find { |t| t.view["services"].any? { |s| s["kind"] == "temple" } }
    expect(town.view["npcs"].find { |n| n["service"] == "temple" }["title"]).to eq("Keeper of #{town.view["services"].find { |s| s["kind"] == "temple" }["name"]}") if town
    node = campaign.map_nodes.create!(name: "Varn", kind: "town", x: 1, y: 1, visible: true, location: towns.first)
    campaign.place_party!(node)
    get location_path(towns.first)
    expect(response.body).to include("crowns")
  end

  it "reaches the battle: the victory line, the beats broadcast as they happen, and the GM's panel" do
    set_words
    create_character(campaign, name: "Rook")
    battle = start_battle(campaign: campaign)
    expect { battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => battle.party.first["id"], "value" => 5 }, actor: "gm") }
      .to have_broadcasted_to(turbo_stream_for(battle)).with(a_string_including("sets Rook&#39;s Grit to 5."))
    post battle_seat_path(battle), params: { seat: "gm" }
    get battle_panel_path(battle)
    expect(response.body).to include(">Rust-lock<")
    expect(response.body).not_to include(">Poison<")

    battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
    expect(campaign.messages.last.body).to include("crowns").and(include("Victory!"))
    expect(campaign.messages.last.body).not_to include("gil")
  end

  it "names statuses its way on the battle board and in the glossary's labels" do
    set_words
    expect(helper_term("poison")).to eq("Rust-lock")
  end

  def helper_term(token)
    view = ApplicationController.new.view_context
    view.instance_variable_set(:@world, world)
    view.term(token)
  end
end
