# frozen_string_literal: true

# A whole world in one file (docs/HANDOFF.md §7, "Packages"), to take to
# another server or hand to another author: a .zip of world.json and the
# pictures and music it uses (PackageArchive). Importing it makes a new
# world, owned by whoever imported it, as "Copy this world" would
# (World::Copying), from the file instead of from this database.
#
# What travels is the setting:
#   - the world itself: its types and chart, skills, terrain, battle rules,
#     voice, lines and veils, its own words, calendar, origins and history;
#   - every book: Grimoire, Armory, Bestiary, encounter and generator
#     tables, Gazetteer, Compendium (archetypes and their learn tables),
#     with their pictures;
#   - its canon: maps, places, roads, cast (with portraits and sprites),
#     fronts, the codex;
#   - its music, uploaded or linked.
# Not its campaigns: a campaign's prep travels as a module (CampaignModule).
#
#   WorldPackage::Export.new(world).to_zip                       # => String (the .zip)
#   WorldPackage::Import.new(zip, owner: user).run!              # => World
module WorldPackage
  FORMAT = "polychrome-world"
  VERSION = 1

  # The world's own fields that travel, as World::Copying copies them.
  SETTING = %w[description damage_types terrain_types skills voice avoid lines veils terms calendar origins history battle_rules].freeze
end
