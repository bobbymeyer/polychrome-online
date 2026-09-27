# frozen_string_literal: true

# Seeds the base world. Safe to re-run: it only adds entries that are missing,
# and never overwrites one a GM may have edited (bin/rails base_world:update does).
require_relative "seeds/base_world"

world = Seeds::BaseWorld.run
puts "Seeded #{world.name}: #{world.abilities.count} abilities, #{world.items.count} items, " \
     "#{world.jobs.count} jobs, #{world.monsters.count} monsters"
