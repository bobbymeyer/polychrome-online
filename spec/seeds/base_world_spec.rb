# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe Seeds::BaseWorld do
  # The suite's ready-made world (spec/support/base_world.rb), seeded from nothing at the start of the
  # run by this very seeder: no need to build it again for each example. What an example changes
  # in it rolls back with the example.
  let(:world) { base_world }

  it "seeds every book" do
    expect(world.slug).to eq("base")
    expect(world.abilities.count).to be >= 12
    expect(world.items.count).to be >= 12
    expect(world.jobs.count).to be >= 6
    expect(world.monsters.count).to be >= 10
  end

  it "is idempotent" do
    counts = -> { [ World.count, Ability.count, Item.count, Job.count, JobLevel.count, Monster.count ] }
    expect { described_class.run }.not_to(change(&counts))
  end

  it "leaves every entry valid" do
    [ world.abilities, world.items, world.jobs, world.monsters, JobLevel.all, world.encounter_tables,
      world.generator_tables, world.location_templates ].each do |scope|
      scope.each { |entry| expect(entry).to be_valid, "#{entry.class} #{entry.try(:slug)}: #{entry.errors.full_messages}" }
    end
  end

  # The books are only useful if the engine can run what they describe.
  it "runs every monster through the engine against a party built from the Compendium" do
    base = { max_hp: 150, max_mp: 30, str: 12, mag: 12, vit: 12, spr: 12, agi: 12 }
    party = world.jobs.where.not(slug: "freelancer").order(:name).map do |job|
      gear = world.items.select { |item| item.equipment? && job.equips?(item) }.group_by(&:slot).values.map(&:first)
      stats = Stats::Derivation.derive(base: base, job: job.to_derivation, equipment: gear.map(&:to_equipment),
                                       passives: job.passives)
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

  it "only adds what's missing when re-run, so a GM's edits survive a deploy" do
    goblin = world.monsters.find_by!(slug: "goblin")
    goblin.update!(name: "Bog Goblin", exp: 99)
    knight = world.jobs.find_by!(slug: "knight")
    knight.job_levels.last.destroy!
    world.monsters.find_by!(slug: "ogre").delete # gone missing (a GM can't delete one the tables still roll)

    described_class.run
    expect(goblin.reload).to have_attributes(name: "Bog Goblin", exp: 99)
    expect(knight.reload.job_levels.count).to eq(5) # the one the GM took out stays out
    expect(world.monsters.find_by(slug: "ogre")).to be_present # the missing one is back
  end

  it "puts everything back when asked to overwrite" do
    world.monsters.find_by!(slug: "goblin").update!(name: "Bog Goblin")
    world.jobs.find_by!(slug: "knight").job_levels.last.destroy!

    described_class.run(overwrite: true)
    expect(world.monsters.find_by!(slug: "goblin").name).to eq("Goblin")
    expect(world.jobs.find_by!(slug: "knight").job_levels.count).to eq(6)
  end

  it "gives every job a desperation move aimed at enemies, found rather than learned" do
    world.jobs.each do |job|
      move = job.desperation_ability
      expect(move).to be_present, job.slug
      expect(move.target).to match(/enemy|enemies/)
      expect(world.jobs.flat_map { |j| j.abilities.map(&:slug) }).not_to include(move.slug)
    end
  end

  it "gives every job a signature command, and has the new jobs with their own arts" do
    world.jobs.each { |job| expect(job.signature_ability).to be_present, job.slug }
    expect(world.jobs.pluck(:slug)).to include("red_mage", "summoner", "geomancer", "dragoon")
    expect(world.jobs.where.not(passive: nil).count).to be >= 8
    expect(world.abilities.find_by!(slug: "gaia").effects.first).to include("type" => "terrain")
  end

  it "gives every kind of gear a job uses a ladder of four, the first two sold in a village and the next in a port" do
    # What any job but the Freelancer (who can hold anything) uses.
    used = world.jobs.where.not(slug: "freelancer").flat_map(&:equip_categories).uniq - %w[accessory]
    used.each do |category|
      ladder = world.items.where(category: category).order(:price)
      expect(ladder.size).to be >= 4, "#{category} has #{ladder.size} steps"
      power = ladder.map { |item| item.stats.values_at("atk", "def", "mag", "spr").compact.sum }
      expect(power).to eq(power.sort), "#{category} doesn't get better as it gets dearer"
    end
    village = world.generator_tables.find_by!(slug: "village_stock").entries.map { |e| e["item"] }
    port = world.generator_tables.find_by!(slug: "shop_stock").entries.map { |e| e["item"] }
    expect(world.items.where(slug: village).where.not(category: "consumable").pluck(:category).uniq).to include(*used)
    expect(world.items.where(slug: port).maximum(:price)).to be > world.items.where(slug: village).maximum(:price)
  end

  it "teaches every job something new every few fights, to a capstone at job level 50; the climb after is mastery" do
    world.jobs.find_each do |job|
      levels = job.job_levels.map(&:level)
      expect(levels.last).to eq(50), job.name
      expect(levels.each_cons(2).map { |a, b| b - a }.max).to be <= 16, "#{job.name} has a long gap"
    end
  end
end
