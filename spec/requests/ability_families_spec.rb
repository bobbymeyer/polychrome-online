# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ability families", type: :request do
  let(:world) { create_world }
  let!(:mage) { create_job(world, slug: "fire_mage") }

  it "writes four tiers from a root, a type and a shape, into a job's learn table" do
    get new_world_grimoire_family_path(world)
    expect(response.body).to include("New ability family", "Caster: damage of a type")

    post world_grimoire_families_path(world), params: { family: { root: "Fire", shape: "caster", type: "fire", job_id: mage.id } }
    expect(response).to redirect_to(world_grimoire_abilities_path(world))
    expect(flash[:notice]).to eq("Wrote Fire, Fira, Firaga, and Firaja into the Fire mage's learn table.")

    firaga = world.abilities.find_by!(slug: "firaga")
    expect(firaga).to have_attributes(kind: "magic", target: "all_enemies", mp_cost: 14)
    expect(firaga.effects).to eq([ { "primitive" => "elemental", "type" => "fire", "power" => 14 } ])
    expect(mage.job_levels.map { |l| [ l.ability.name, l.level ] }).to eq([ [ "Fire", 1 ], [ "Fira", 20 ], [ "Firaga", 40 ], [ "Firaja", 60 ] ])
  end

  it "takes the author's names and numbers, and any shape: here a hexer" do
    post world_grimoire_families_path(world), params: { family: { root: "Hex", shape: "hexer", status: "poison",
                                                                  tiers: { "0" => { name: "Blight", power: "40" }, "3" => { name: "Plague", mp: "30" } } } }
    expect(world.abilities.find_by!(slug: "blight").effects.first).to include("kind" => "poison", "chance" => 40)
    expect(world.abilities.find_by!(slug: "plague")).to have_attributes(mp_cost: 30, target: "all_enemies")
    expect(world.abilities.pluck(:name)).to include("Hexa", "Hexaga")
  end

  it "writes nothing if any tier can't be written" do
    create_ability(world, slug: "fira")
    post world_grimoire_families_path(world), params: { family: { root: "Fire", shape: "caster", type: "fire" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Fira: Slug has already been taken")
    expect(world.abilities.where(slug: %w[firaga firaja])).to be_empty
  end

  it "needs a type the world has for a caster" do
    post world_grimoire_families_path(world), params: { family: { root: "Zap", shape: "caster", type: "plasma" } }
    expect(response.body).to include("Type must be one of Testland")
  end
end
