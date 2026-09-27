# frozen_string_literal: true

require "rails_helper"

RSpec.describe Job do
  let(:world) { create_world }

  it "normalises multipliers, dropping blanks and 100%" do
    job = world.jobs.new(name: "Monk", stat_multipliers: { "str" => "130", "agi" => "", "vit" => "100" })
    expect(job.stat_multipliers).to eq("str" => 130)
    expect(job).to be_valid
  end

  it "validates multipliers, equip categories and innates" do
    job = world.jobs.new(name: "Odd", stat_multipliers: { "luck" => "120", "str" => "900" },
                         equip_categories: %w[sword lightsaber],
                         innates: { "0" => { "stat" => "charm", "add" => "5" }, "1" => { "stat" => "agi" } })
    expect(job).not_to be_valid
    expect(job.errors[:stat_multipliers]).to include(/unknown stats: luck/, /0 to 500 \(str/)
    expect(job.errors[:equip_categories]).to include(/lightsaber/)
    expect(job.errors[:innates]).to include("charm is not a stat", "agi needs a whole-number add or percent")
  end

  it "keeps a learn table of abilities from its own world" do
    job = create_job(world)
    cure = create_ability(world, slug: "cure", target: "single_ally", effects: [ { primitive: "heal", power: 10 } ])
    alien = create_ability(create_world(slug: "other"), slug: "cure")

    job.update!(job_levels_attributes: [ { level: 1, ability_id: cure.id }, { level: "", ability_id: "" } ])
    expect(job.job_levels.map { |l| [ l.level, l.ability.slug ] }).to eq([ [ 1, "cure" ] ])
    expect(cure.jobs).to eq([ job ])

    expect(job.update(job_levels_attributes: [ { level: 2, ability_id: alien.id } ])).to be(false)
    expect(job.errors.full_messages.to_sentence).to match(/Grimoire/)
  end

  it "feeds Stats::Derivation" do
    job = create_job(world, stat_multipliers: { str: 150 }, innates: [ { stat: "agi", add: 5 } ])
    sword = create_item(world, stats: { atk: 12 })
    stats = Stats::Derivation.derive(base: { str: 10, agi: 10, max_hp: 100 }, job: job.to_derivation,
                                     equipment: [ sword.to_equipment ], passives: job.passives)
    expect(stats).to include("str" => 15, "agi" => 15, "atk" => 12)
    expect(job.equips?(sword)).to be(true)
  end

  it "takes a desperation move aimed at enemies, from its own Grimoire" do
    create_ability(world, slug: "cure", kind: "magic", target: "single_ally", effects: [ { primitive: "heal", power: 20 } ])
    create_ability(world, slug: "big_hit", kind: "skill", target: "single_enemy", effects: [ { primitive: "physical", power: 200 } ])
    job = create_job(world)
    expect(job.update(desperation: "cure")).to be(false)
    expect(job.errors[:desperation]).to include("must be aimed at enemies")
    expect(job.update(desperation: "nothing")).to be(false)
    expect(job.update(desperation: "big_hit")).to be(true)
    expect(job.desperation_ability.slug).to eq("big_hit")
    expect(job.update(desperation: "")).to be(true)
    expect(job.reload.desperation).to be_nil
  end

  it "takes a signature command from its Grimoire and a passive from the engine's list" do
    create_ability(world, slug: "cover", kind: "skill", target: "self", effects: [ { primitive: "status", kind: "cover", duration: 2 } ])
    job = create_job(world)
    expect(job.update(signature: "nothing")).to be(false)
    expect(job.update(passive: "flying")).to be(false)
    expect(job.update(signature: "cover", passive: "second_wind")).to be(true)
    expect(job.signature_ability.slug).to eq("cover")
  end
end
