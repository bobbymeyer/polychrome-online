# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe Seeds::BaseWorld do
  let!(:world) { described_class.run }

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
end
