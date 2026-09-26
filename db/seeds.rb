# frozen_string_literal: true

# Seeds the base world. Safe to re-run: entries are matched by slug.
require_relative "seeds/base_world"

world = Seeds::BaseWorld.run
puts "Seeded #{world.name}: #{world.abilities.count} abilities, #{world.items.count} items, " \
     "#{world.jobs.count} jobs, #{world.monsters.count} monsters"
