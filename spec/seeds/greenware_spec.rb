# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/greenware")

# The second seeded setting: everything the Base World doesn't lean on, this
# one does, so it's the proof that another author can build their own.
RSpec.describe Seeds::Greenware do
  # Seeded once for the file, outside the examples' transactions (so what an example changes rolls
  # back), and taken down after: the suite keeps only the base world.
  before(:all) do
    World.where(slug: "greenware").destroy_all
    described_class.run
  end
  after(:all) { World.where(slug: "greenware").destroy_all }

  let(:world) { World.find_by!(slug: "greenware") }

  def gm(name) = User.create!(name: name, email_address: "#{name.parameterize}@example.com", password: "a-long-enough-password")

  it "seeds every book and the whole canon" do
    expect(world.slug).to eq("greenware")
    expect(world.abilities.count).to be >= 90
    expect(world.items.count).to be >= 50
    expect(world.jobs.count).to eq(9)
    expect(world.monsters.count).to be >= 20
    expect(world.world_places.count).to eq(10)
    expect(world.world_routes.count).to eq(11)
    expect(world.world_figures.count).to be >= 6
    expect(world.world_fronts.count).to be >= 2
    expect(world.codex_entries.count).to be >= 9
  end

  it "writes its pocket history into the canon, around the pasts it wrote itself" do
    expect(Chronicle.new(world)).to be_written
    expect(world.codex_entries.pluck(:title)).to include("The last 120 years", "The Vask family", "The Weld family")
    expect(world.world_figures.where.not(history_key: nil).count).to be >= 3
    expect(world.world_places.find_by!(name: "The Great Kiln").past).to include("was" => "kiln", "edited" => true)
    expect(Past.new(world.world_places.find_by!(name: "Clay Pits of Harrow").past, lore: world.lore).to_s).to include("Marl Harrow never came out")
  end

  it "is idempotent" do
    counts = -> { [ World.count, Ability.count, Item.count, Job.count, JobLevel.count, Monster.count, WorldPlace.count, WorldRoute.count, CodexEntry.count, WorldFigure.count, WorldFront.count ] }
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

  it "is its own setting: types, skills, origins, words and a calendar that counts to the Firing" do
    expect(world.type_chart.plain).to eq("clay")
    expect(world.type_chart.percent("fire", "clay")).to eq(200)
    expect(world.terrain_type("crypt")).to eq("bone")
    expect(world.skills.map { |s| s["slug"] }).to include("firing", "reading", "haggling")
    expect(world.origins.map { |o| o["skill"] }).to all(satisfy { |skill| world.skill(skill) })
    expect(world.money(1500)).to eq("1,500 cones")
    expect(world.word("hp")).to eq("Body")
    expect(world.word("status.doom")).to eq("Firing")
    expect(world.date(1)).to eq("Loadday, 49 Green")
    expect(world.almanac.season_and_year(1)).to eq("Dry · Cold Kiln 40")
    expect(world.date(13)).to eq("Loadday, 1 Cone") # the clock has twelve segments, and ticks each new day
    expect(world.rule?("one_more")).to be(true)
  end

  it "writes its things to do in the calendar's words" do
    world.world_places.where.not(activities: [ nil, "" ]).each do |place|
      pastimes, problems = Pastime.parse(place.activities, world.almanac)
      expect(problems).to be_empty, "#{place.name}: #{problems}"
      expect(pastimes).not_to be_empty
    end
  end

  # The books are only useful if the engine can run what they describe.
  it "runs every monster through the engine against a party built from the Compendium" do
    base = { max_hp: 150, max_mp: 30, str: 12, mag: 12, vit: 12, spr: 12, agi: 12 }
    party = world.jobs.where.not(slug: "greenhand").order(:name).map do |job|
      gear = world.items.select { |item| item.equipment? && job.equips?(item) }.group_by(&:slot).values.map(&:first)
      stats = Stats::Derivation.derive(base: base, job: job.to_derivation, equipment: gear.map(&:to_equipment), passives: job.passives)
      { id: job.slug, name: job.name, stats: stats, abilities: job.abilities.pluck(:slug) }
    end.first(4)

    world.monsters.find_each do |monster|
      state = world.battle(seed: monster.id, party: party, monsters: { monster.slug => 2 })
      60.times do
        break unless state["status"] == "input"

        state, = Battle::Resolver.apply(state, { type: "timeout" })
      end
      expect(%w[victory defeat input]).to include(state["status"])
    end
  end

  it "gives every archetype a signature, a field ability, a desperation move aimed at enemies, and a payoff" do
    world.jobs.each do |job|
      expect(job.signature_ability).to be_present, job.slug
      expect(job.field_ability_entry).to be_present, job.slug
      expect(job.desperation_ability).to be_present, job.slug
      expect(%w[single_enemy all_enemies random_enemy]).to include(job.desperation_ability.target)
      expect(job.payoff["kind"]).to be_present, job.slug
      expect(job.job_levels.count).to be >= 6
    end
  end

  it "starts a campaign in Cone with the whole valley, its leads, its night faces and its fronts" do
    campaign = world.campaigns.create!(name: "The Last Soft Summer", gm: gm("Kiln GM"))
    campaign.set_out!(from_the_setting: true)
    expect(campaign.map_nodes.count).to eq(10)
    expect(campaign.current_node.name).to eq("Cone")
    expect(campaign.map_edges.count).to eq(11)
    expect(campaign.map_nodes.where(visible: false).pluck(:name)).to contain_exactly("Clay Pits of Harrow", "The Misfire Vaults", "The Old Saltworks", "Cone-Reader's Tower")
    expect(campaign.rumours.count).to be >= 4 # one lead per unknown place
    expect(campaign.map_nodes.find_by!(name: "Cone").modes.pluck(:name)).to include("By night")
    expect(campaign.npcs.pluck(:name)).to include("Kilnmaster Orrin Vask", "Sister Weld")
    expect(campaign.clocks.pluck(:name)).to include("The Kiln is loaded", "The sheds empty", "The Harrow galleries spread")
    expect(campaign.secrets.count).to be >= 6
    expect(campaign.map_nodes.find_by!(name: "Cone").modes.pluck(:name)).to include("Firing")
    expect(campaign.world.date(campaign.day)).to eq("Loadday, 49 Green")
  end

  it "rolls its own towns and dungeons from its own tables" do
    campaign = world.campaigns.create!(name: "Rolling", gm: gm("Roller"))
    campaign.set_out!(from_the_setting: true)
    cone = campaign.map_nodes.find_by!(name: "Cone").location
    expect(cone.view["services"].map { |s| s["kind"] }).to include("inn", "shop", "guild")
    expect(cone.view["npcs"].size).to be >= 5
    pits = campaign.map_nodes.find_by!(name: "Clay Pits of Harrow").location
    expect(pits.view["rooms"].size).to be >= 5
    boss = pits.view["rooms"].find { |r| r["key"] == pits.view["boss"] }
    expect(boss["decision"]["kind"]).to eq("boss")
  end

  it "puts everything back when asked to overwrite" do
    world.monsters.find_by!(slug: "slip_hound").update!(name: "Mud Dog")
    world.jobs.find_by!(slug: "thrower").job_levels.last.destroy!

    described_class.run(overwrite: true)
    expect(world.monsters.find_by!(slug: "slip_hound").name).to eq("Slip Hound")
    expect(world.jobs.find_by!(slug: "thrower").job_levels.count).to eq(6)
  end
end
