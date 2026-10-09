# frozen_string_literal: true

# Encounter tables and generator tables: what's met on a mesa road, and what
# Oda's towns, mines and forts are rolled from. (Seeds::Oda)
module Seeds
  module Oda
    ENCOUNTER_TABLES = {
      mesa_road: { name: "Mesa road", terrain: "plains", tier: 1,
                   description: "Red dust, long shadows, and things that wait in both.",
                   entries: [ { weight: 4, monsters: { dust_coyote: 3 } }, { weight: 3, monsters: { road_bandit: 2 } },
                              { weight: 2, monsters: { powder_rat: 3 } }, { weight: 1, monsters: { road_bandit: 1, dust_coyote: 2 } } ] },
      powder_flats: { name: "Powder flats", terrain: "desert", tier: 1,
                      description: "Where the seams come to the surface and the ground crunches underfoot.",
                      entries: [ { weight: 3, monsters: { powder_rat: 3 } }, { weight: 3, monsters: { storm_crow: 2 } },
                                 { weight: 2, monsters: { rust_lizard: 1, powder_rat: 1 } } ] },
      the_seam: { name: "The Deep Seam", terrain: "cave", tier: 2,
                  description: "The Company's galleries, and what came up them.",
                  entries: [ { weight: 3, monsters: { seam_crawler: 2 } }, { weight: 3, monsters: { company_rifleman: 2 } },
                             { weight: 2, monsters: { seam_crawler: 1, rust_lizard: 1 } } ] },
      fort_cinder: { name: "Fort Cinder", terrain: "mountain", tier: 2,
                     description: "Bandits who refused their duels, and the guns they bought with what they stole.",
                     entries: [ { weight: 4, monsters: { road_bandit: 3 } }, { weight: 2, monsters: { gunhand: 1, road_bandit: 1 } },
                                { weight: 2, monsters: { company_rifleman: 2 } } ] },
      the_belfry: { name: "Drowned Belfry", terrain: "sea", tier: 2,
                    description: "A bell tower in a flooded valley, and the salt that walks in it.",
                    entries: [ { weight: 3, monsters: { salt_wraith: 1 } }, { weight: 2, monsters: { salt_wraith: 1, storm_crow: 2 } },
                               { weight: 2, monsters: { storm_crow: 3 } } ] }
    }.freeze

    GENERATOR_TABLES = {
      town_names: { name: "Town names", kind: "town_names",
                    entries: texts("Noonbell", "Saltpeter", "Gearhold", "Redwater", "Long Shadow", "Dry Creek", "Fuse", "Lantern Rock", "Brimstone",
                                   "Crossing", "Hightable", "Quarter Mile", "Copperhead", "Kettle", "Windlass", "Ochre", "Tumbleweed", "Mesa Gate") },
      mine_names: { name: "Mine names", kind: "dungeon_names",
                    entries: texts("The Deep Seam", "Company Shaft Nine", "The Red Gallery", "The Glowing Drift", "Old Kindle Mine", "The Long Dark") },
      fort_names: { name: "Fort names", kind: "dungeon_names",
                    entries: texts("Fort Cinder", "The Coward's Keep", "Smoke Fort", "Gallows Bluff", "The Stockade") },
      belfry_names: { name: "Belfry names", kind: "dungeon_names",
                      entries: texts("The Drowned Belfry", "The Sunken Bell", "Low Tower", "The Waiting Bell") },
      given_names: { name: "Given names", kind: "names",
                     entries: texts("Silas", "Ines", "Wade", "Marrow", "Quill", "Hale", "Rook", "Sable", "Tam", "Juno", "Abel", "Mercy", "Cass", "Dell", "Ezra",
                                    "Faye", "Gil", "Hollis", "Ivy", "Jory", "Kit", "Lark", "Mags", "Nash", "Ona", "Pike", "Reed", "Sage", "Tully", "Vane",
                                    "Wren", "Yara", "Zeke", "Bram", "Clem", "Dove", "Esme", "Flint", "Gale", "Harrow") },
      family_names: { name: "Families", kind: "families",
                      entries: texts("Crane", "Vey", "Ashdown", "Bellweather", "Coldwater", "Drummond", "Esk", "Fallow", "Gage", "Holloway",
                                     "Ironside", "Kettering", "Lowe", "Mallory", "Noon", "Orchard", "Pike", "Redfern", "Sallow", "Thorne") },
      hooks: { name: "Townsfolk hooks", kind: "hooks",
               entries: texts("Refused a duel twenty years ago, and still pays the shame price at every counter.",
                              "Wants an escort to {town} and won't say who's following.", "Has a duelling pistol in a locked box. Won't say whose it was.",
                              "Heard the ground breathe under {dungeon}.", "Keeps a tally of the Smiling Draw's duels on the back of a door.",
                              "Sells powder that's been cut with sand.", "Lost a brother to the Deep Seam; the Company sent his boots back.",
                              "Rings the noon bell, and has never once seen the duel through.", "Is looking for someone to fight a duel in their place. That isn't allowed. They know.",
                              "Saw a giant's shadow on the mesa at dusk, walking.", "Has a map to an old seam, half burned.",
                              "Owes the Powder Company more than they'll earn in their life.", "Was a Courtsword once. Their sheath is empty now.",
                              "Swears the Drowned Belfry rings at noon, under the water.", "Builds little clockwork birds and sells them to children.",
                              "Wants word taken to a clockmaker in Gearhold.") },
      townsfolk_memories: { name: "Townsfolk memories", kind: "memories",
                            entries: texts("I saw the Smiling Draw's first duel. The other one was laughing too, right until noon.",
                                           "I mined the Deep Seam for nine years. I heard it breathing in the eighth.",
                                           "My father refused a duel. We moved three times before I was ten.",
                                           "I saw a giant once, far off on the mesa. I couldn't look at it for long.",
                                           "I rang the bell for a duel nobody came to. I rang it until dusk.",
                                           "I ran from {town} the night the ground split.") },
      townsfolk_wishes: { name: "Townsfolk wishes", kind: "wishes",
                          entries: texts("I want the Company out of {town} before the next seam opens.", "I'd like to see the Smiling Draw lose. Just once.",
                                         "I'm saving for a wheellock and the nerve to use it.", "I want to know what's under {dungeon}.") +
                                   [ { text: "My boy is powder-sick from the seam. A draught would buy him a month.", item: "charcoal_draught" },
                                     { text: "My partner's down and won't wake. Salts, if you have them.", item: "smelling_salts" },
                                     { text: "I can't see for the dust. An eyewash would do it.", item: "eyewash" } ] },
      arrivals: { name: "Arrivals", kind: "arrivals",
                  entries: [ { text: "{place}. Red dust on everything, and the shadows short." },
                             { text: "{place} at Noon: the street empties, and somebody waits under the bell.", when: "town, noon" },
                             { text: "{place} again. The same faces, and they've heard about you.", when: "town, visits >= 2" },
                             { text: "The doors of {place} close a little as the party passes. Someone says the word, quietly.", when: "town, cowards >= 1" },
                             { text: "The air at the mouth of {place} hums, and tastes of powder.", when: "dungeon, first_visit" },
                             { text: "{place} is quiet now.", when: "dungeon, cleared" } ] },
      complications: { name: "Complications", kind: "complications",
                       entries: [ { text: "Somebody saw. Somebody always sees, in a small town." },
                                  { text: "A stranger in the street calls {who} out. It isn't a request.", when: "town" },
                                  { text: "The ground shifts underfoot: the seams are moving.", when: "dungeon", does: "ambush" },
                                  { text: "It costs: a bribe, a fine, a round for the house.", when: "town", does: "lose 50" },
                                  { text: "Dust, heat and a long walk.", does: "weary 25" } ] },
      service_names: { name: "Service names", kind: "service_names",
                       entries: texts("The Long Noon", "The Empty Holster", "Bell & Board", "The Last Match", service: "inn") +
                                texts("Powder & Sundries", "The Gearbox", "Coldwater Outfitters", service: "shop") +
                                texts("The Bell Tower", "The Noon Tower", service: "guild") +
                                texts("The Healer's House", "Sallow's Apothecary", service: "temple") },
      buildings: { name: "Building archetypes", kind: "buildings",
                   entries: [ { text: "Boarding house", service: "inn", width: 90, height: 80, roof: "flat" },
                              { text: "Outfitter", service: "shop", width: 70, height: 70, roof: "flat" },
                              { text: "Bell tower", service: "guild", width: 40, height: 150, roof: "peak" },
                              { text: "Healer's house", service: "temple", width: 70, height: 80, roof: "peak" },
                              { text: "Powder store", width: 60, height: 50, roof: "dome", weight: 2 },
                              { text: "Saloon", width: 80, height: 70, roof: "flat", weight: 2 },
                              { text: "Clocktower", width: 36, height: 130, roof: "peak" },
                              { text: "Adobe house", width: 50, height: 45, roof: "flat", weight: 4 },
                              { text: "Water tower", width: 30, height: 110, roof: "dome" } ] },
      town_stock: { name: "Town stock", kind: "stock",
                    entries: %w[tonic strong_tonic smelling_salts charcoal_draught eyewash smoke_pot fire_shot thunder_shot water_shot stone_shot wind_shot
                                court_blade stiletto charge_rod healers_staff mesa_bow wheellock duster monks_wrap mancers_robe lacquered_hat
                                powder_horn lucky_mark iron_bracer].map { |item| { item: item } } },
      clock_stock: { name: "Gearhold stock", kind: "stock",
                     entries: %w[tonic strong_tonic smelling_salts panacea charcoal_draught noon_blade quay_knife seam_rod bell_staff long_rifle brigandine
                                 mancers_robe lacquered_hat powder_horn].map { |item| { item: item } } },
      mine_rooms: { name: "Mine rooms", kind: "rooms",
                    entries: texts("Pithead", "Cage Shaft", "Powder Store", "Gallery", "Glowing Drift", "Foreman's Hut", "Flooded Sump", "Crystal Face",
                                   "Ore Chute", "The Breathing Wall", "Company Office", "The Deepest Face") },
      fort_rooms: { name: "Fort rooms", kind: "rooms",
                    entries: texts("Gate", "Stockade Yard", "Armoury", "Watchtower", "Cookhouse", "Strongroom", "Stables", "Chief's Quarters", "Powder Magazine") },
      belfry_rooms: { name: "Belfry rooms", kind: "rooms",
                      entries: texts("Drowned Nave", "Bell Stair", "Ringing Chamber", "Vestry", "Salt Cellar", "Clock Room", "The Bell Itself") },
      room_events: { name: "Room events", kind: "room_events",
                     entries: texts("A duel's chalk circle on the floor, and two sets of boot marks. One set leaves fast.",
                                    "A seam of raw powder in the wall, pulsing like a slow heart.",
                                    "A company notice: DANGER, NO DIGGING BELOW THIS MARK. Someone has dug below it.",
                                    "A clockwork bird, wound down, holding a note in its beak.",
                                    "Someone's left a pistol-shaped space in the dust on a shelf.",
                                    "The floor is warm, and the warmth is coming up.",
                                    "A bell rope hangs from nowhere, and sways.") },
      forks: { name: "Fork costs", kind: "forks",
               entries: texts("A ladder down a dry well: someone stays to hold it.", "Powder fumes: everyone who goes this way loses a tenth of their Grit. (hurt 10)",
                              "A Company gate that opens for 100 marks. (pay 100)", "Loose ore: the noise will wake what sleeps below. (ambush)",
                              "A long crawl: it takes half the day. (2)") },
      traps: { name: "Traps", kind: "traps",
               entries: texts("A tripwire and a powder charge. (hurt 20)", "A pit under loose boards. (hurt 10, 1)",
                              "A pressure plate, and the room fills with grey powder. (weary 25)", "A bell on a wire: everything below hears it. (ambush)",
                              "A spring-gun aimed at the door. (hurt 15)", "Salt dust that eats into the lungs. (hurt 10, weary 10)") },
      locks: { name: "Locks and keys", kind: "locks",
               entries: [ { text: "Company padlock", key: "Foreman's ring of keys" }, { text: "Clockwork door", key: "A wound key" },
                          { text: "Strongroom", key: "The chief's seal" }, { text: "Drowned grate", key: "Bell-pull chain" } ] },
      treasure: { name: "Dungeon treasure", kind: "treasure",
                  entries: [ { item: "tonic", weight: 8 }, { item: "strong_tonic", weight: 4 }, { item: "smelling_salts", weight: 4 },
                             { item: "charcoal_draught", weight: 4 }, { item: "panacea", weight: 2 }, { item: "fire_shot", weight: 3 },
                             { item: "thunder_shot", weight: 3 }, { item: "noon_blade" }, { item: "long_rifle" }, { item: "seam_rod" },
                             { gil: 60, weight: 6 }, { gil: 150, weight: 4 }, { gil: 400, weight: 2 } ] }
    }.freeze

    # The land's lore (Generators::Lore): what its places' pasts are made of.
    LORE = {
      "trades" => { "miner" => [], "gunsmith" => %w[pistol rifle], "clockmaker" => %w[clock watch], "mancer" => [ "powder horn" ],
                    "rancher" => [] },
      "pasts" => {
        "mine" => { "rooms" => [ "Pithead", "Cage Shaft", "Gallery", "Powder Store", "Crystal Face" ],
                    "heart" => "The Deepest Face", "keeps" => [ "pick", "lamp", "tally" ], "named" => %w[mine seam shaft drift gallery] },
        "fort" => { "rooms" => [ "Gate", "Stockade Yard", "Armoury", "Watchtower", "Strongroom" ],
                    "heart" => "The Strongroom", "keeps" => [ "badge", "pistol", "ledger" ], "named" => %w[fort keep stockade bluff] },
        "belfry" => { "rooms" => [ "Nave", "Bell Stair", "Ringing Chamber", "Clock Room" ],
                      "heart" => "The Bell", "keeps" => [ "bell clapper", "rope", "hymnal" ], "named" => %w[belfry bell tower] }
      },
      "falls" => {
        "cave_in" => { "did" => "fell in", "sealed" => "shored up and left", "trace" => "Timbers snapped like matches, and dust that never settled.",
                       "dead" => "who were below", "town" => "The ground opened under %s" },
        "flood" => { "did" => "flooded", "sealed" => "left to the water", "trace" => "A tide line up the walls, and salt on everything.",
                     "dead" => "who drowned in it", "town" => "The river came through %s" },
        "waking" => { "did" => "woke", "sealed" => "sealed with powder charges", "trace" => "Claw marks the size of doors, and the walls still warm.",
                      "dead" => "who were digging", "town" => "Something woke under %s" }
      },
      "quarrels" => [ "a duel refused", "a claim jumped", "a horse sold lame", "a seam both families swore they found", "a debt to the Company" ],
      "betrayals" => [ "sold the claim to the Company", "testified for the bought sheriff", "stood second in a duel and stepped in" ],
      "fortunes" => [ "a seam of pure red salt", "a strongbox found in a dry well", "a duel won against the odds" ],
      "waters" => [ "the creek", "the drowned valley", "the water tower" ],
      "owners" => [ "Lost by a %s in a duel", "Sold by the %s family after the cave-in", "Won at cards from a %s" ],
      "sightings" => [ "{who} was seen in {where}, with a hand near their gun." ],
      "raids" => [ "A powder wagon between {from} and {to} was taken, and its drivers sent home on foot." ]
    }.freeze

    LORE_NAMES = { "trades" => "Trades", "pasts" => "What the mines and forts were", "falls" => "How places fall", "quarrels" => "Quarrels",
                   "betrayals" => "Betrayals", "fortunes" => "Good fortune", "waters" => "Waters", "owners" => "Changing hands",
                   "sightings" => "Sightings", "raids" => "Raided roads" }.freeze
    LORE_TABLES = Generators::Lore.to_tables(LORE).to_h do |kind, entries|
      [ :"lore_#{kind}", { name: LORE_NAMES.fetch(kind), kind: kind, entries: entries } ]
    end.freeze
  end
end
