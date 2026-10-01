# frozen_string_literal: true

# The base world's first book entries (docs/HANDOFF.md §2: "The base world
# is seed data: the first World and its children").
#
# Worlds are live: a GM develops theirs as they play, editing entries in the
# books. So an ordinary run only adds what's missing (a new monster, a new
# table) and never touches an entry that's already there, edited or not.
# `bin/rails base_world:update` (overwrite: true) puts every entry back to
# what's written here, for when the seed data itself has been retuned.
# Numbers are first-pass tuning (§9.2). The writing is Seeds::Setting's.
require_relative "setting"

module Seeds
  module BaseWorld
    extend Helpers
    module_function

    def run(overwrite: false)
      Setting.new(
        slug: "base",
        world: { name: "Base World",
                 description: "The opinionated default setting: crystals, jobs, and a world map of towns, " \
                              "dungeons and the roads between them.",
                 damage_types: TypeChart.default_rows, terrain_types: TypeChart::DEFAULT_TERRAIN, skills: World::DEFAULT_SKILLS },
        abilities: ABILITIES, items: ITEMS, monsters: MONSTERS, encounter_tables: ENCOUNTER_TABLES,
        generator_tables: GENERATOR_TABLES.merge(LORE_TABLES), location_templates: LOCATION_TEMPLATES, jobs: JOBS, payoffs: PAYOFFS,
        places: PLACES, routes: ROUTES, figures: FIGURES, fronts: FRONTS
      ).run(overwrite: overwrite)
    end
  end
end

# The books, by file: each defines its constants inside Seeds::BaseWorld.
require_relative "base_world/abilities"
require_relative "base_world/items"
require_relative "base_world/jobs"
require_relative "base_world/monsters"
require_relative "base_world/tables"
require_relative "base_world/atlas"
require_relative "base_world/templates"
