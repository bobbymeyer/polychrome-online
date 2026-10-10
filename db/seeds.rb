# frozen_string_literal: true

# Seeds Oda (docs/ODA.md): the first world and, on a fresh database, the
# only one. Safe to re-run: it only adds entries that are missing, and
# never overwrites one a GM may have edited (bin/rails
# worlds:update[oda] does).
#
# The Base World (db/seeds/base_world/) and Greenware
# (db/seeds/greenware/) are still written and still seedable one at a time
# — bin/rails worlds:seed[base_world], worlds:seed[greenware] — and the
# suite builds the Base World for its own fixtures (spec/support/
# base_world.rb). They are just not what a new database starts as any
# more: Oda is the setting being played, and the first world is the one
# the others are copied from (World.root).
require_relative "seeds/oda"

world = Seeds::Oda.run
puts "Seeded #{world.name}: #{world.abilities.count} abilities, #{world.items.count} items, " \
     "#{world.jobs.count} archetypes, #{world.monsters.count} monsters, " \
     "#{world.world_places.count} places, #{world.codex_entries.count} codex pages"
