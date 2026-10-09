# frozen_string_literal: true

# Seeds the base world, Greenware, the second setting (the proof that
# another author can build their own from the same books), and Oda, the
# third (docs/ODA.md). Safe to re-run:
# it only adds entries that are missing, and never overwrites one a GM may
# have edited (bin/rails base_world:update and worlds:update[slug] do).
require_relative "seeds/base_world"
require_relative "seeds/greenware"
require_relative "seeds/oda"

[ Seeds::BaseWorld, Seeds::Greenware, Seeds::Oda ].each do |seed|
  world = seed.run
  puts "Seeded #{world.name}: #{world.abilities.count} abilities, #{world.items.count} items, " \
       "#{world.jobs.count} jobs, #{world.monsters.count} monsters"
end
