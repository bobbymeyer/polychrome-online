# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A world's types", type: :request do
  let(:world) { create_world }
  let!(:bomb) { create_monster(world, slug: "bomb", base_type: "fire", affinities: { "water" => "weak", "fire" => "absorb" }) }
  let!(:fire) { create_ability(world) }
  let!(:knight) { create_job(world, base_type: "steel") }

  # The editor's form for every current type, with some removed.
  def rows(remove: {}, rename: {})
    world.type_chart.types.each_with_index.to_h do |t, i|
      row = { slug: t.slug, name: rename.fetch(t.slug, t.name), colour: t.colour, shrugs_off: t.shrugs_off }
      row.merge!(remove: "1", send_to: remove[t.slug]) if remove.key?(t.slug)
      [ i.to_s, row ]
    end
  end

  it "shows what uses each type, for the editor" do
    get edit_world_types_path(world)
    expect(response.body).to include("Bomb", "Fire", "Knight", "Edit types")
  end

  it "folds a whole setting into one type, dropping the affinities that no longer mean anything" do
    everything_but_normal = world.type_chart.slugs.excluding("normal").index_with { "normal" }
    patch world_types_path(world), params: { types: rows(remove: everything_but_normal), plain: "normal" }
    expect(response).to redirect_to(world_types_path(world))
    follow_redirect!
    expect(response.body).to include("Now Normal: Fire, Bomb, and Knight.", "Dropped Bomb: absorb Fire and Bomb: weak Water.")
    expect(response.body).to include("has one type, Normal")

    expect(world.reload.type_chart.slugs).to eq(%w[normal])
    expect(bomb.reload).to have_attributes(base_type: "normal", affinities: {})
    expect(fire.reload.effects.first["type"]).to eq("normal")
    expect(knight.reload.base_type).to eq("normal")
    expect(world.terrain_types.values.uniq).to eq(%w[normal])

    get world_bestiary_monster_path(world, bomb)
    expect(response.body).not_to include("type-tag")
    get edit_world_bestiary_monster_path(world, bomb)
    expect(response.body).not_to include("monster_base_type\">")
  end

  it "won't remove a type without somewhere for its uses to go" do
    patch world_types_path(world), params: { types: rows(remove: { "fire" => "" }) }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Fire is being removed: pick a type")
    expect(world.reload.type_chart).to include("fire")
  end

  it "renames, adds a type and charts it, and battles use the world's chart" do
    new_row = { name: "Holy", colour: "#f0e68c" }
    patch world_types_path(world), params: { types: rows(rename: { "ghost" => "Spirit" }).merge("99" => new_row), plain: "normal",
                                              chart: { "fire" => { "holy" => "50" }, "holy" => { "ghost" => "200" } } }
    chart = world.reload.type_chart
    expect(chart.name("ghost")).to eq("Spirit")
    expect(chart.slugs.last).to eq("holy")
    expect(chart.percent("fire", "holy")).to eq(50)
    expect(chart.percent("fire", "grass")).to eq(100) # cells not posted are ordinary: the form posts them all

    state = world.battle(seed: 1, party: [], monsters: { "bomb" => 1 })
    expect(Battle::Types.list(state["types"])).to include("holy")
  end

  it "lets only the world's editors change it" do
    sign_in_as(make_user("Player"))
    get edit_world_types_path(world)
    expect(flash[:alert]).to match(/can change Testland/)
    patch world_types_path(world), params: { types: rows(remove: { "fire" => "normal" }) }
    expect(world.reload.type_chart).to include("fire")
    get world_types_path(world)
    expect(response).to have_http_status(:ok)
  end

  it "gives a new world one type, and a copy its source's" do
    post worlds_path, params: { world: { name: "Plainland" } }
    expect(World.find_by!(slug: "plainland").type_chart.slugs).to eq(%w[normal])
    post worlds_path(copy_from: world.slug), params: { world: { name: "Copyland" } }
    expect(World.find_by!(slug: "copyland").type_chart.slugs).to eq(world.type_chart.slugs)
  end
end
