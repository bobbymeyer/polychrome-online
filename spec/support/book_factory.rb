# frozen_string_literal: true

# Minimal valid book entries for Rails specs. Plain methods, no factory gem.
module BookFactory
  # With the base world's types, unless given its own.
  def create_world(slug: "testland", name: "Testland", damage_types: TypeChart.default_rows)
    World.create!(slug: slug, name: name, damage_types: damage_types, terrain_types: TypeChart::DEFAULT_TERRAIN.select { |_, t| damage_types.any? { |r| r["slug"] == t } })
  end

  def monster_stats(**overrides)
    { max_hp: 50, max_mp: 0, str: 10, mag: 10, vit: 10, spr: 10, agi: 10, atk: 8, def: 3, mdef: 3 }
      .merge(overrides).stringify_keys
  end

  def create_ability(world, slug: "fire", **attrs)
    world.abilities.create!({ slug: slug, name: slug.humanize, kind: "magic", target: "single_enemy", mp_cost: 4,
                              effects: [ { primitive: "elemental", type: "fire", power: 20 } ] }.merge(attrs))
  end

  def create_item(world, slug: "sword", **attrs)
    world.items.create!({ slug: slug, name: slug.humanize, category: "sword", stats: { atk: 10 } }.merge(attrs))
  end

  def create_monster(world, slug: "goblin", **attrs)
    world.monsters.create!({ slug: slug, name: slug.humanize, stats: monster_stats, ai_script: [ { use: "attack" } ] }.merge(attrs))
  end

  def create_job(world, slug: "knight", **attrs)
    world.jobs.create!({ slug: slug, name: slug.humanize, stat_multipliers: { str: 120 }, equip_categories: %w[sword] }.merge(attrs))
  end
end

RSpec.configure do |config|
  config.include BookFactory
end

# A campaign with two knights, and battles for them against goblins.
module BattleFactory
  def knight_world
    world = create_world
    cure = create_ability(world, slug: "cure", kind: "magic", target: "single_ally", effects: [ { primitive: "heal", power: 20 } ])
    create_item(world)
    create_job(world).job_levels.create!(level: 1, ability: cure)
    create_monster(world, exp: 10, gil: 5, abp: 2)
    world
  end

  def create_campaign(world: knight_world, name: "The Crystal Road")
    world.campaigns.create!(name: name)
  end

  def create_character(campaign, name: "Bartz", job: nil, **attrs)
    job ||= campaign.world.jobs.find_by!(slug: "knight")
    campaign.characters.create!({ name: name, job: job, starting_level: 5, starting_job_level: 1 }.merge(attrs))
  end

  def start_battle(campaign: nil, goblins: 2, input_seconds: nil, seed: 7, **options)
    campaign ||= create_campaign
    characters = campaign.characters.order(:created_at).to_a
    characters = [ create_character(campaign, name: "Bartz"), create_character(campaign, name: "Faris") ] if characters.empty?
    BattleRecord.start!(campaign: campaign, characters: characters, name: "Test battle", encounter: { "goblin" => goblins },
                        seed: seed, input_seconds: input_seconds, **options)
  end

  def turbo_stream_for(record)
    record.to_gid_param # the stream name Turbo broadcasts to for a single record
  end
end

RSpec.configure do |config|
  config.include BattleFactory
end
