# frozen_string_literal: true

# Oda's types are Pokémon's eighteen now (docs/ODA.md, Bobby's call), and
# the seed says so; a database seeded before has Oda's old eight. This
# moves it over: the chart through TypeChange, which sends each old type's
# uses to its new home (thunder to Electric, earth to Ground, wind to
# Flying, shot to Steel, deep to Dragon) and keeps battles already running
# on the chart they started with. Then every entry the seeds wrote (Oda's,
# and The Just Seven's in Oda's books) takes the type the seed now gives it:
# the Thief is Dark, the Crab Rock, the Viper Poison and Grass. Only the
# types: names, numbers and scripts a GM has changed stay theirs.
class RetypeOdaAsPokemon < ActiveRecord::Migration[8.1]
  SENDS = { "thunder" => "electric", "earth" => "ground", "wind" => "flying", "shot" => "steel", "deep" => "dragon" }.freeze

  def up
    world = World.find_by(slug: "oda") or return
    return if world.type_chart.slugs.include?("fairy")

    require Rails.root.join("db/seeds/oda").to_s
    require Rails.root.join("db/seeds/campaigns/just_seven").to_s
    change = TypeChange.new(world, rows: Seeds::Oda::DAMAGE_TYPES.map(&:deep_dup), sends: SENDS.slice(*world.type_chart.slugs),
                                   terrain: Seeds::Oda::TERRAIN_TYPES)
    raise "Oda's types couldn't change: #{world.errors.full_messages.to_sentence}" unless change.save

    retype(world, Seeds::Oda::ABILITIES.merge(Seeds::JustSeven::ABILITIES), Seeds::Oda::ITEMS.merge(Seeds::JustSeven::ITEMS),
           Seeds::Oda::MONSTERS.merge(Seeds::JustSeven::MONSTERS), Seeds::Oda::JOBS)
  end

  def down
    # The old chart is gone from the seed; TypeChange in the types editor goes anywhere from here.
  end

  private

  def retype(world, abilities, items, monsters, jobs)
    world.abilities.where(slug: abilities.keys.map(&:to_s)).find_each do |entry|
      entry.update_columns(effects: typed_effects(entry.effects, abilities.fetch(entry.slug.to_sym)[:effects]))
    end
    world.items.where(slug: items.keys.map(&:to_s)).find_each do |entry|
      seed = items.fetch(entry.slug.to_sym).deep_stringify_keys
      changes = { effects: typed_effects(entry.effects, seed["effects"]) }
      changes[:mask] = entry.mask.merge("type" => seed.dig("mask", "type")) if entry.mask.present? && seed.dig("mask", "type")
      entry.update_columns(changes)
    end
    world.monsters.where(slug: monsters.keys.map(&:to_s)).find_each do |entry|
      seed = monsters.fetch(entry.slug.to_sym).deep_stringify_keys
      entry.update_columns(base_type: seed["base_type"], second_type: seed["second_type"], affinities: seed.fetch("affinities", {}))
    end
    world.jobs.where(slug: jobs.keys.map(&:to_s)).find_each do |entry|
      entry.update_columns(base_type: jobs.fetch(entry.slug.to_sym)[:base_type])
    end
  end

  # Each effect takes the type the seed's effect in its place has, where the two still line up.
  def typed_effects(effects, seeded)
    seeded = Array(seeded).map(&:deep_stringify_keys)
    Array(effects).each_with_index.map do |effect, i|
      written = seeded[i]
      written && written["primitive"] == effect["primitive"] && written["type"] ? effect.merge("type" => written["type"]) : effect
    end
  end
end
