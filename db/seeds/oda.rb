# frozen_string_literal: true

# Oda: the third seeded setting (docs/ODA.md), and the home of its
# archetypes: the Courtsword, the five Mancers, the Thief, the Monk, the
# Magician, the Healer and the Ranger.
#
# A land of red mesas and terraced valleys at the edge of the Reach, where
# the ground holds powder: elemental salts ground from crystal seams,
# measured into cartridges and paper charms and fired through barrels,
# staves and talismans. A gun is a cheap, dumb caster; a Mancer is the
# expensive, clever kind. Dig deep enough after the good seams and things
# wake up: giants of raw powder that grow when they're hurt. Oda has no
# masks of its own: there are seven in all, and they belong to one
# campaign, The Just Seven (db/seeds/campaigns/just_seven).
#
# Everyone in Oda knows one law: someone who refuses a duel is a coward,
# and a coward has no place in this world. A duel is one against one, three
# swings each on a meter (Duel, DuelMeter).
#
# The tone swaps (the GM's to steer): one session a grim frontier, the next
# a bright one with a masked hero and a monster of the week. Its genres are
# JRPG, tokusatsu, samurai films and westerns, and its people are its own.
#
# Seeded by db:seed, or alone with bin/rails worlds:seed[oda];
# bin/rails worlds:update[oda] puts every entry back to this.
require_relative "setting"

module Seeds
  module Oda
    extend Helpers
    module_function

    def run(overwrite: false)
      Setting.new(
        slug: "oda",
        world: WORLD,
        abilities: ABILITIES, items: ITEMS, monsters: MONSTERS, encounter_tables: ENCOUNTER_TABLES,
        generator_tables: GENERATOR_TABLES.merge(LORE_TABLES), location_templates: LOCATION_TEMPLATES, jobs: JOBS, payoffs: PAYOFFS,
        places: PLACES, routes: ROUTES, figures: FIGURES, fronts: FRONTS, codex: CODEX
      ).run(overwrite: overwrite)
    end

    # --- the setting itself ------------------------------------------------------

    # Pokémon's eighteen types (Bobby's call): the base world's chart
    # (Battle::Types), which leaves out Dragon and Fairy, with those two put
    # back. Normal is the plain one. The five powders are Fire, Water,
    # Electric, Ground and Flying; guns fire Steel; the giants are Dragon.
    POKEMON_CHART = Battle::Types::CHART.to_h { |type, row| [ type, row.dup ] }.tap do |chart|
      { "fire" => { "dragon" => 50 }, "water" => { "dragon" => 50 }, "electric" => { "dragon" => 50 }, "grass" => { "dragon" => 50 },
        "ice" => { "dragon" => 200 }, "fighting" => { "fairy" => 50 }, "poison" => { "fairy" => 200 }, "bug" => { "fairy" => 50 },
        "dark" => { "fairy" => 50 }, "steel" => { "fairy" => 200 } }.each { |type, more| chart.fetch(type).merge!(more) }
      chart["dragon"] = { "dragon" => 200, "steel" => 50, "fairy" => 0 }
      chart["fairy"] = { "fire" => 50, "fighting" => 200, "poison" => 50, "dragon" => 200, "dark" => 200, "steel" => 50 }
    end.freeze

    TYPE_LOOKS = {
      "normal" => [ "Normal", "#a8a878" ], "fire" => [ "Fire", "#f08030" ], "water" => [ "Water", "#6890f0" ], "electric" => [ "Electric", "#f8d030" ],
      "grass" => [ "Grass", "#78c850" ], "ice" => [ "Ice", "#98d8d8" ], "fighting" => [ "Fighting", "#c03028" ], "poison" => [ "Poison", "#a040a0" ],
      "ground" => [ "Ground", "#e0c068" ], "flying" => [ "Flying", "#a890f0" ], "psychic" => [ "Psychic", "#f85888" ], "bug" => [ "Bug", "#a8b820" ],
      "rock" => [ "Rock", "#b8a038" ], "ghost" => [ "Ghost", "#705898" ], "dragon" => [ "Dragon", "#7038f8" ], "dark" => [ "Dark", "#705848" ],
      "steel" => [ "Steel", "#b8b8d0" ], "fairy" => [ "Fairy", "#ee99ac" ]
    }.freeze

    # As in the games: fire can't be burned, electric paralysed, poison or steel poisoned.
    SHRUGS_OFF = { "fire" => %w[burn], "electric" => %w[paralyze], "poison" => %w[poison], "steel" => %w[poison] }.freeze

    DAMAGE_TYPES = TYPE_LOOKS.map do |slug, (name, colour)|
      { "slug" => slug, "name" => name, "colour" => colour, "shrugs_off" => SHRUGS_OFF.fetch(slug, []), "against" => POKEMON_CHART.fetch(slug) }
    end.freeze

    TERRAIN_TYPES = { "plains" => "normal", "forest" => "grass", "desert" => "ground", "mountain" => "rock",
                      "cave" => "rock", "crypt" => "ghost", "sea" => "water", "town" => "normal" }.freeze

    SKILLS = [
      { "slug" => "draw", "name" => "Draw", "stat" => "agi", "description" => "Getting there first: a blade, a pistol, a hand to a falling cup." },
      { "slug" => "nerve", "name" => "Nerve", "stat" => "spr", "description" => "Standing still while someone stares you down. Not blinking. Not running." },
      { "slug" => "trail", "name" => "Trail", "stat" => "vit", "description" => "Tracks, weather, water, the long ride, what's safe to eat in the Reach." },
      { "slug" => "hands", "name" => "Hands", "stat" => "agi", "description" => "Locks, pockets, cards, knots: quick, exact work." },
      { "slug" => "powdercraft", "name" => "Powdercraft", "stat" => "mag", "description" => "Reading a seam, a measure, a charm: what powder is and what it will do." },
      { "slug" => "clockwork", "name" => "Clockwork", "stat" => "mag", "description" => "Springs, gears, locks and the little machines that run on a pinch of powder." },
      { "slug" => "brawn", "name" => "Brawn", "stat" => "str", "description" => "Lifting, hauling, breaking a door, holding a horse." },
      { "slug" => "parley", "name" => "Parley", "stat" => "spr", "description" => "Talking someone round, or down, or out of a duel they'd win." }
    ].freeze

    ORIGINS = [
      { "slug" => "seam_born", "name" => "Seam-born", "skill" => "powdercraft",
        "description" => "Raised in a powder camp at the Reach's edge. You can tell a good seam by the taste, and you've lost friends to a bad one." },
      { "slug" => "noonbell_raised", "name" => "Noonbell-raised", "skill" => "nerve",
        "description" => "You grew up under the bell that rings for duels. You've watched a hundred. You know how still people go, just before." },
      { "slug" => "gearhold_apprentice", "name" => "Gearhold apprentice", "skill" => "clockwork",
        "description" => "Seven years at a clockmaker's bench in Gearhold, and a quarrel with your master that ended it." },
      { "slug" => "mesa_rider", "name" => "Mesa rider", "skill" => "trail",
        "description" => "You rode messages between the mesa towns before you could read them. Every road is yours." },
      { "slug" => "quay_rat", "name" => "Quay rat", "skill" => "hands",
        "description" => "Saltpeter's quays: crates, cards and other people's purses." },
      { "slug" => "temple_foundling", "name" => "Temple foundling", "skill" => "brawn",
        "description" => "Left at a Monk house's gate and raised on its forms. You can carry a bell up a mountain, and have." }
    ].freeze

    # Dawn, Noon, Dusk, Night: duels are fought at Noon, by custom if not by
    # law. A six-day week; four seasons of three months, and the story starts
    # in the Dry, with the Long Noon coming.
    CALENDAR = {
      "periods" => %w[Dawn Noon Dusk Night], "dark" => %w[Night],
      "weekdays" => %w[Firstday Tradeday Mineday Bellday Restday Masqueday],
      "months" => [ { "name" => "Thaw", "days" => 30, "season" => "Wet" }, { "name" => "Rain", "days" => 30, "season" => "Wet" },
                    { "name" => "Bloom", "days" => 30, "season" => "Wet" }, { "name" => "Kindle", "days" => 30, "season" => "Dry" },
                    { "name" => "Long Noon", "days" => 30, "season" => "Dry" }, { "name" => "Ember", "days" => 30, "season" => "Dry" },
                    { "name" => "Harvest", "days" => 30, "season" => "Gold" }, { "name" => "Reckoning", "days" => 30, "season" => "Gold" },
                    { "name" => "Ash", "days" => 30, "season" => "Gold" }, { "name" => "Frost", "days" => 30, "season" => "Cold" },
                    { "name" => "Deepwinter", "days" => 30, "season" => "Cold" }, { "name" => "Thinning", "days" => 30, "season" => "Cold" } ],
      "start" => { "year" => 412, "month" => 3, "day" => 18, "weekday" => 3 },
      "eras" => [ { "label" => "Year # of the Seams", "from" => 1 } ]
    }.freeze

    TERMS = {
      "currency" => "marks", "hp" => "Grit", "mp" => "Powder",
      "stats" => { "spr" => "Nerve" },
      "services" => { "inn" => "Boarding house", "shop" => "Outfitter", "guild" => "Bell tower", "temple" => "Healer's house" },
      "statuses" => { "poison" => "Powder-sick", "sleep" => "Asleep", "berserk" => "Bloodied", "doom" => "Marked", "charged" => "Drawn breath",
                      "sheathed" => "Sheathed", "chi" => "Chi", "iai" => "Iai stance", "masked" => "Masked", "spent" => "Spent", "reloading" => "Reloading" }
    }.freeze

    WORLD = {
      name: "Oda",
      description: "Red mesas, terraced valleys and the Reach beyond them, where the ground holds powder: elemental salts that the mancers " \
                   "load and fire, the gunsmiths pack into shot, and the mines dig deeper for every year. Dig too deep and something " \
                   "wakes. Everyone knows one law: whoever refuses a duel is a coward, and a coward has no place in this world.",
      voice: "Laconic, sunlit, a little dusty; long silences and short lines. Duels are quiet until they aren't. The tone swaps on purpose: " \
             "one week a grim frontier of powder-sick miners and bought sheriffs, the next a bright one with a masked hero, a monster of " \
             "the week and a sunset. Touchstones: Seven Samurai and The Magnificent Seven, Wild ARMs, Kamen Rider, Sergio Leone's close-ups.",
      avoid: "real-world cultures and their names, honour as a lecture, chosen ones, prophecy, gunpowder as the only magic",
      lines: "Harm to children on-screen",
      veils: "What the deep does to a miner who digs too far (told, after)",
      damage_types: DAMAGE_TYPES, terrain_types: TERRAIN_TYPES, skills: SKILLS, origins: ORIGINS,
      calendar: CALENDAR, terms: TERMS, battle_rules: { "same_type" => true }
    }.freeze
  end
end

# The books and the canon, by file: each defines its constants inside Seeds::Oda.
require_relative "oda/abilities"
require_relative "oda/items"
require_relative "oda/jobs"
require_relative "oda/monsters"
require_relative "oda/tables"
require_relative "oda/templates"
require_relative "oda/atlas"
require_relative "oda/codex"
