# frozen_string_literal: true

require "rails_helper"

# What histories and the pasts of places are made of is each world's own
# (Generators::Lore), in its generator tables, edited like the rest.
RSpec.describe "A world's lore", type: :request do
  let(:world) { World.create!(name: "Undertow", slug: "undertow_lore", owner: @admin).tap { |w| w.copy_books_from!(base_world, rules_only: true) } }

  it "comes with a copy of the world it started from, as tables its author edits" do
    expect(world.lore["pasts"].keys).to include("manor", "abbey")
    expect(world.generator_tables.where(kind: GeneratorTable::LORE_KINDS).pluck(:kind)).to match_array(GeneratorTable::LORE_KINDS)

    pasts = world.generator_tables.find_by!(kind: "pasts")
    patch world_generation_generator_table_path(world, pasts), params: { generator_table: {
      name: pasts.name, kind: "pasts", entries: { "0" => { text: "" } },
      paste: "station | Ticket Hall, Platform 2, Signal Box | The Last Platform | ticket, lamp | station, line"
    } }
    expect(world.reload.lore["pasts"]).to eq("station" => { "rooms" => [ "Ticket Hall", "Platform 2", "Signal Box" ], "heart" => "The Last Platform",
                                                            "keeps" => %w[ticket lamp], "named" => %w[station line] })
    expect(Generators::Lore.was_for("Tsukiura Station", world.lore)).to eq("station")

    place = world.world_places.create!(name: "The Drowned Line", kind: "dungeon", x: 5, y: 5)
    get edit_world_world_place_path(world, place)
    expect(response.body).to include(%(<option value="station">Station</option>))
    expect(response.body).not_to include(%(<option value="manor">))
  end

  it "says the world's own words overnight, and nothing where it has none" do
    world.generator_tables.find_by!(kind: "sightings").update!(entries: [ { "text" => "Someone saw {who} on the last train to {where}." } ])
    world.generator_tables.find_by!(kind: "raids").destroy!
    campaign = world.campaigns.create!(name: "Night Shift", gm: @admin)
    varn = campaign.map_nodes.create!(name: "Varn", kind: "town", x: 1, y: 1, visible: true)
    tule = campaign.map_nodes.create!(name: "Tule", kind: "town", x: 9, y: 9, visible: true)
    mara = campaign.npcs.create!(name: "Mara")
    night = [ { "kind" => "moved", "npc" => mara.id, "name" => "Mara", "from" => varn.id, "to" => tule.id },
              { "kind" => "caravan", "from" => varn.id, "to" => tule.id } ]
    allow(Pointcrawl::Overnight).to receive(:run) { |_state, rng| [ rng, night ] }
    campaign.update!(time_of_day: "night")
    campaign.pass_time!(1)
    expect(campaign.rumours.pluck(:body)).to eq([ "Someone saw Mara on the last train to Tule." ])
  end
end
