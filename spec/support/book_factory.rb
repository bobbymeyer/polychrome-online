# frozen_string_literal: true

# Minimal valid book entries for Rails specs. Plain methods, no factory gem.
module BookFactory
  def create_world(slug: "testland", name: "Testland")
    World.create!(slug: slug, name: name)
  end

  def monster_stats(**overrides)
    { max_hp: 50, max_mp: 0, str: 10, mag: 10, vit: 10, spr: 10, agi: 10, atk: 8, def: 3, mdef: 3 }
      .merge(overrides).stringify_keys
  end

  def create_ability(world, slug: "fire", **attrs)
    world.abilities.create!({ slug: slug, name: slug.humanize, kind: "magic", target: "single_enemy", mp_cost: 4,
                              effects: [ { primitive: "elemental", element: "fire", power: 20 } ] }.merge(attrs))
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

# A battle started from minimal books: two knights against goblins.
module BattleFactory
  def start_battle(world: nil, goblins: 2, input_seconds: nil, seed: 7, **options)
    world ||= create_world
    create_ability(world, slug: "cure", kind: "magic", target: "single_ally", effects: [ { primitive: "heal", power: 20 } ]) unless world.abilities.exists?(slug: "cure")
    unless world.jobs.exists?(slug: "knight")
      create_item(world) unless world.items.exists?(slug: "sword")
      create_job(world).job_levels.create!(level: 1, abp: 10, ability: world.abilities.find_by!(slug: "cure"))
    end
    create_monster(world) unless world.monsters.exists?(slug: "goblin")
    party = QuickParty.new(world).build([ { name: "Bartz", job: "knight" }, { name: "Faris", job: "knight" } ])
    BattleRecord.start!(world: world, name: "Test battle", party: party, encounter: { "goblin" => goblins },
                        seed: seed, input_seconds: input_seconds, **options)
  end

  def turbo_stream_for(record)
    record.to_gid_param # the stream name Turbo broadcasts to for a single record
  end
end

RSpec.configure do |config|
  config.include BattleFactory
end
