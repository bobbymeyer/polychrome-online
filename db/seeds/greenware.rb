# frozen_string_literal: true

# Greenware: the second seeded setting, written against the same books as
# the Base World to prove another author can (docs/HANDOFF.md §1).
#
# A valley of kiln-towns whose people are clay. Fired, you are finished:
# hard, lasting, and whatever you were when the fire found you. The Great
# Kiln at Cone has been cold for forty years, and a generation has grown up
# unfired: soft, mortal, and able to change. The player characters are that
# generation (that's why they have archetypes and can change them), and the
# Kilnmasters mean to light the Kiln again on the first of Cone, twelve days
# after a campaign begins.
#
# Where the Base World is Final Fantasy, this is pulp with a craft trade's
# plainness: the dread is in the vocabulary (crazing, leather-hard, the
# Firing), never in a prophecy. Every system the Base World doesn't lean
# on, this one does: its own damage types and chart, its own skills and
# origins, words over the game's (Body and Slip, cones, drying sheds), a
# calendar whose parts of the day are a potter's (Wedging, Throwing,
# Drying, Cooling) and whose months count to the Firing, places with things
# to do and a face by night, fronts with a public clock that fills on the
# date the setting names, and One More on.
#
# Seeded by db:seed, or alone with bin/rails worlds:seed[greenware];
# bin/rails worlds:update[greenware] puts every entry back to this.
require_relative "setting"

module Seeds
  module Greenware
    extend Helpers
    module_function

    def run(overwrite: false)
      Setting.new(
        slug: "greenware",
        world: WORLD,
        abilities: ABILITIES, items: ITEMS, monsters: MONSTERS, encounter_tables: ENCOUNTER_TABLES,
        generator_tables: GENERATOR_TABLES.merge(LORE_TABLES), location_templates: LOCATION_TEMPLATES, jobs: JOBS, payoffs: PAYOFFS,
        places: PLACES, routes: ROUTES, figures: FIGURES, fronts: FRONTS, codex: CODEX, history: HISTORY
      ).run(overwrite: overwrite)
    end

    # --- the setting itself ------------------------------------------------------

    # Six types, and a chart a potter would recognise: fire finishes clay,
    # water slakes it, glass cuts it; ash fluxes glass; bone is the misfired
    # and the dead. The first type is the plain one.
    DAMAGE_TYPES = [
      { "slug" => "clay", "name" => "Clay", "colour" => "#b5651d", "shrugs_off" => [], "against" => { "water" => 200 } },
      { "slug" => "fire", "name" => "Fire", "colour" => "#e8702a", "shrugs_off" => %w[doom], "against" => { "clay" => 200, "bone" => 200, "water" => 50, "glass" => 50, "fire" => 50 } },
      { "slug" => "water", "name" => "Water", "colour" => "#4f82e8", "shrugs_off" => %w[sleep], "against" => { "fire" => 200, "clay" => 200, "glass" => 50, "water" => 50 } },
      { "slug" => "ash", "name" => "Ash", "colour" => "#8c8c7a", "shrugs_off" => %w[blind], "against" => { "glass" => 200, "water" => 200, "fire" => 50, "ash" => 50 } },
      { "slug" => "glass", "name" => "Glass", "colour" => "#7fd0cc", "shrugs_off" => %w[poison doom], "against" => { "bone" => 200, "clay" => 200, "fire" => 50, "glass" => 50 } },
      { "slug" => "bone", "name" => "Bone", "colour" => "#d9cfae", "shrugs_off" => %w[poison sleep doom], "against" => { "ash" => 200, "fire" => 50, "glass" => 50, "bone" => 50 } }
    ].freeze

    TERRAIN_TYPES = { "plains" => "clay", "forest" => "ash", "desert" => "glass", "mountain" => "fire",
                      "cave" => "clay", "crypt" => "bone", "sea" => "water", "town" => "clay" }.freeze

    SKILLS = [
      { "slug" => "heft", "name" => "Heft", "stat" => "str", "description" => "Lifting, hauling, shouldering a kiln door shut." },
      { "slug" => "standing", "name" => "Standing", "stat" => "vit", "description" => "Standing the heat, the cold, the long walk, the long wait." },
      { "slug" => "softfoot", "name" => "Softfoot", "stat" => "agi", "description" => "Not being seen or heard, in a valley where everything echoes off fired walls." },
      { "slug" => "hands", "name" => "Hands", "stat" => "agi", "description" => "Throwing, trimming, latches, pockets: quick, exact work." },
      { "slug" => "firing", "name" => "Firing", "stat" => "mag", "description" => "Reading heat by its colour, a cone by its bend, a glaze by its recipe, an old mark by its maker." },
      { "slug" => "reading", "name" => "Reading", "stat" => "spr", "description" => "Reading a person, a crack, a lie: where it will go when it's pressed." },
      { "slug" => "roadcraft", "name" => "Roadcraft", "stat" => "vit", "description" => "Towpaths, weather, where the barges tie up and what's safe to eat." },
      { "slug" => "haggling", "name" => "Haggling", "stat" => "spr", "description" => "Talking someone round, or down, in a valley that prices everything in cones." }
    ].freeze

    ORIGINS = [
      { "slug" => "pit_born", "name" => "Pit-born", "skill" => "heft",
        "description" => "Dug from Harrow clay and raised at the pit edge. You can carry anything, and you have." },
      { "slug" => "shed_raised", "name" => "Shed-raised", "skill" => "hands",
        "description" => "Grew up among Bisque's drying racks, turning pots so they wouldn't warp. Quick, careful hands." },
      { "slug" => "kiln_family", "name" => "Kilnmaster's child", "skill" => "firing",
        "description" => "Your parent was fired young and perfect. You weren't, yet. You know the Kiln from inside the family and outside the door." },
      { "slug" => "menders_ward", "name" => "Mender's ward", "skill" => "reading",
        "description" => "Raised in a Menders' house among the cracked and the glued. You see where a thing will break before it does." },
      { "slug" => "barge_child", "name" => "Barge child", "skill" => "roadcraft",
        "description" => "Born on a clay barge between Slipway and the sea. Every road is a river to you." },
      { "slug" => "flats_walker", "name" => "From the Glass Flats", "skill" => "standing",
        "description" => "Your people salvage glass where the Second Kiln blew. Heat, cold, and bare feet on sharp ground." },
      { "slug" => "unmarked", "name" => "Unmarked", "skill" => "softfoot",
        "description" => "No maker's mark on your heel. Nobody knows whose clay you are, so you learned not to be noticed." }
    ].freeze

    # A potter's day, a kiln's week, and six months that count down to the
    # Firing: the story starts on 49 Green, twelve days before 1 Cone.
    CALENDAR = {
      "periods" => %w[Wedging Throwing Drying Cooling], "dark" => %w[Cooling],
      "weekdays" => %w[Loadday Lightday Stokeday Soakday Crackday Restday],
      "months" => [ { "name" => "Thaw", "days" => 60, "season" => "Wet" }, { "name" => "Slurry", "days" => 60, "season" => "Wet" },
                    { "name" => "Green", "days" => 60, "season" => "Dry" }, { "name" => "Cone", "days" => 60, "season" => "Firing" },
                    { "name" => "Ash", "days" => 60, "season" => "Firing" }, { "name" => "Frost", "days" => 60, "season" => "Cold" } ],
      "start" => { "year" => 40, "month" => 2, "day" => 49, "weekday" => 0 },
      "eras" => [ { "label" => "Cold Kiln #", "from" => 1 } ]
    }.freeze

    TERMS = {
      "currency" => "cones", "hp" => "Body", "mp" => "Slip",
      "stats" => { "str" => "Heft", "mag" => "Glaze", "vit" => "Grog", "spr" => "Temper", "agi" => "Wheel" },
      "services" => { "inn" => "Drying shed", "shop" => "Supply", "guild" => "Kiln Hall", "temple" => "Menders" },
      "statuses" => { "poison" => "Crazing", "sleep" => "Leather-hard", "paralyze" => "Bone-dry", "silence" => "Choked", "blind" => "Slip-eyed",
                      "slow" => "Thick slip", "confuse" => "Warped", "berserk" => "Overfired", "stop" => "Cooled", "doom" => "Firing" }
    }.freeze

    WORLD = {
      name: "Greenware",
      description: "A valley of kiln-towns whose people are clay. Fired, you are finished: hard, lasting, and whatever you were when " \
                   "the fire found you. The Great Kiln at Cone has been cold for forty years, and a generation has grown up unfired: " \
                   "soft, mortal, and able to change. The Kilnmasters mean to light it again on the first of Cone.",
      voice: "Workshop plain. Tactile words: wedge, slip, grog, crazing, soak. People talk about bodies the way potters talk about " \
             "clay, without horror. Short lines, dry humour; nobody says destiny. Touchstones: Earthsea for the plainness, a Ghibli " \
             "workshop for the warmth, Dark Souls item descriptions for the dread.",
      avoid: "crystals, prophecy, chosen one, ancient evil, taverns, elves, mana",
      lines: "Harm to children on-screen\nThe firing of an unwilling person shown in detail",
      veils: "What the Firing feels like (only ever told, after)\nThe Vaults' lower shelves",
      damage_types: DAMAGE_TYPES, terrain_types: TERRAIN_TYPES, skills: SKILLS, origins: ORIGINS,
      calendar: CALENDAR, terms: TERMS, battle_rules: { "one_more" => true }
    }.freeze

    # The pocket history (Chronicle), rolled over the atlas and written into
    # the canon: a fixed seed, so it's the same history every time, and the
    # families the setting already names, kept through rerolls. The Kiln,
    # the pits, the Vaults and the saltworks write their own pasts (atlas.rb).
    HISTORY = { seed: 1_960_040, years: 120, write: true,
                families: [ { name: "Vask", trade: "potter", seat: "Cone" }, { name: "Harrow", trade: "digger", seat: "Slipway" },
                            { name: "Weld", trade: "mender", seat: "Bisque" }, { name: "Grell", trade: "cone-reader", seat: "Cone-Reader's Tower" } ] }.freeze
  end
end

# The books and the canon, by file: each defines its constants inside Seeds::Greenware.
require_relative "greenware/abilities"
require_relative "greenware/items"
require_relative "greenware/jobs"
require_relative "greenware/monsters"
require_relative "greenware/tables"
require_relative "greenware/templates"
require_relative "greenware/atlas"
require_relative "greenware/codex"
