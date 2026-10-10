# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/oda")

# The third seeded setting, and the home of Oda's archetypes (docs/ODA.md).
RSpec.describe Seeds::Oda do
  before { World.where(slug: "oda").destroy_all }

  let!(:world) { described_class.run }

  def gm(name) = User.create!(name: name, email_address: "#{name.parameterize}@example.com", password: "a-long-enough-password")

  it "seeds the thirteen archetypes and the books they need" do
    expect(world.jobs.pluck(:name)).to contain_exactly("Courtsword", "Firemancer", "Watermancer", "Thundermancer", "Earthmancer", "Windmancer",
                                                       "Thief", "Monk", "Magician", "Healer", "Ranger", "Soldier", "Bodyguard")
    expect(world.abilities.count).to be >= 100
    expect(world.items.masks).to be_empty # the seven belong to The Just Seven
    expect(world.monsters.where(giant: true).count).to be >= 2
    expect(world.world_places.count).to eq(8)
    expect(world.world_figures.count).to eq(3)
    expect(world.world_fronts.count).to eq(2)
  end

  it "is idempotent" do
    counts = -> { [ World.count, Ability.count, Item.count, Job.count, JobLevel.count, Monster.count, WorldPlace.count, WorldRoute.count, CodexEntry.count ] }
    expect { described_class.run }.not_to(change(&counts))
  end

  it "leaves every entry valid" do
    [ world.abilities, world.items, world.jobs, world.monsters, JobLevel.joins(:job).where(jobs: { world_id: world.id }), world.encounter_tables,
      world.generator_tables, world.location_templates, world.world_places, world.world_routes, world.world_figures, world.world_fronts,
      world.codex_entries ].each do |scope|
      scope.each { |entry| expect(entry).to be_valid, "#{entry.class} #{entry.try(:slug) || entry.try(:name)}: #{entry.errors.full_messages}" }
    end
    expect(world).to be_valid
  end

  it "has Pokémon's eighteen types and their chart, the powders among them, noon, and powder for MP" do
    expect(world.type_chart.slugs).to eq(%w[normal fire water electric grass ice fighting poison ground flying psychic bug rock ghost dragon dark steel fairy])
    expect(world.type_chart.plain).to eq("normal")
    expect(world.type_chart.percent("water", "fire")).to eq(200)
    expect(world.type_chart.percent("ice", "dragon")).to eq(200)
    expect(world.type_chart.percent("dragon", "fairy")).to eq(0)
    expect(world.type_chart.percent("fairy", "dragon")).to eq(200)
    expect(world.type_chart.percent("steel", "fairy")).to eq(200)
    expect(world.type_chart.percent("normal", "ghost")).to eq(0)
    expect(world.jobs.find_by!(slug: "thundermancer").base_type).to eq("electric")
    expect(world.abilities.find_by!(slug: "aero").effects.first["type"]).to eq("flying")
    expect(world.monsters.find_by!(slug: "seam_giant").types).to eq(%w[dragon ground])
    expect(world.word("mp")).to eq("Powder")
    expect(world.money(1500)).to eq("1,500 marks")
    expect(world.rule?("same_type")).to be(true)
    expect(world.almanac.periods).to include("Noon")
  end

  it "gives every archetype a signature, a field ability, a desperation move and a payoff" do
    world.jobs.each do |job|
      expect(job.signature_ability).to be_present, job.slug
      expect(job.field_ability_entry).to be_present, job.slug
      expect(%w[single_enemy all_enemies random_enemy]).to include(job.desperation_ability&.target), job.slug
      expect(job.payoff["kind"]).to be_present, job.slug
      expect(job.job_levels.count).to be >= 5
    end
    expect(world.jobs.find_by!(slug: "monk").abilities.sum(:mp_cost)).to eq(0) # gave up powder
    expect(world.jobs.find_by!(slug: "healer").passive).to eq("potency")
  end

  it "puts the heavy fighters in plate: the Courtsword, the Soldier, and the Bodyguard in all the best of it" do
    plate = world.items.find_by!(slug: "gearhold_plate")
    wearers = world.jobs.select { |job| job.equips?(plate) }.map(&:name)
    expect(wearers).to contain_exactly("Courtsword", "Soldier", "Bodyguard")
    expect(world.jobs.select { |job| job.equips?(world.items.find_by!(slug: "pavise")) }.map(&:name)).to eq([ "Bodyguard" ])
    expect(world.jobs.find_by!(slug: "bodyguard").passive).to eq("guardian")
    expect(world.generator_tables.find_by!(slug: "clock_stock").entries.map { |e| e["item"] }).to include("gearhold_plate", "pavise", "halberd")
  end

  it "writes the mancers from one form: four measures, a trick, a load" do
    fire = world.jobs.find_by!(slug: "firemancer")
    expect(fire.abilities.pluck(:slug)).to include("fire", "fira", "firaga", "firaja", "scorch")
    expect(world.abilities.find_by!(slug: "firaja").to_engine).to include("reload" => 1)
    expect(world.abilities.find_by!(slug: "firaja").effects.first).to include("unresisted" => 1)
    expect(world.abilities.find_by!(slug: "flame_load").effects.first).to include("primitive" => "imbue", "type" => "fire")
  end

  it "runs every monster through the engine against a party built from the Compendium" do
    base = { max_hp: 150, max_mp: 30, str: 12, mag: 12, vit: 12, spr: 12, agi: 12 }
    party = world.jobs.order(:name).map do |job|
      gear = world.items.select { |item| item.equipment? && !item.mask? && job.equips?(item) }.group_by(&:slot).values.map(&:first)
      stats = Stats::Derivation.derive(base: base, job: job.to_derivation, equipment: gear.map(&:to_equipment), passives: job.passives)
      { id: job.slug, name: job.name, stats: stats, abilities: job.abilities.pluck(:slug) + [ job.signature ] }
    end
    world.monsters.find_each do |monster|
      state = world.battle(seed: monster.id, party: party.sample(4, random: Random.new(monster.id)), monsters: { monster.slug => 2 })
      60.times do
        break unless state["status"] == "input"

        state, = Battle::Resolver.apply(state, { type: "timeout" })
      end
      expect(%w[victory defeat fled input]).to include(state["status"])
    end
  end

  it "starts a campaign in Noonbell with its leads, its cast and its fronts" do
    campaign = world.campaigns.create!(name: "High Noon", gm: gm("Oda GM"))
    campaign.set_out!(from_the_setting: true)
    expect(campaign.current_node.name).to eq("Noonbell")
    expect(campaign.map_nodes.where(visible: false).pluck(:name)).to contain_exactly("Fort Cinder", "The Drowned Belfry")
    expect(campaign.npcs.pluck(:name)).to include("Silas Crane", "Marrow Vey", "Wade Ashdown")
    expect(campaign.duellists.pluck(:name)).to include("Silas Crane")
    expect(campaign.clocks.pluck(:name)).to include("The seam goes deeper", "The Smiling Draw's tally")
  end

  it "rolls its own towns and dungeons" do
    campaign = world.campaigns.create!(name: "Rolling", gm: gm("Roller"))
    campaign.set_out!(from_the_setting: true)
    noonbell = campaign.map_nodes.find_by!(name: "Noonbell").location
    expect(noonbell.view["services"].map { |s| s["kind"] }).to include("inn", "shop", "guild")
    seam = campaign.map_nodes.find_by!(name: "The Deep Seam").location
    expect(seam.view["rooms"].size).to be >= 5
  end

  it "writes its things to do in the calendar's words" do
    world.world_places.where.not(activities: [ nil, "" ]).each do |place|
      pastimes, problems = Pastime.parse(place.activities, world.almanac)
      expect(problems).to be_empty, "#{place.name}: #{problems}"
      expect(pastimes).not_to be_empty
    end
  end
end
