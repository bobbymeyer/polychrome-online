# frozen_string_literal: true

# The Gazetteer: the kinds of town and dungeon in the valley. (Seeds::Greenware)
module Seeds
  module Greenware
    LOCATION_TEMPLATES = {
      kiln_town: { name: "Kiln-town", kind: "town", description: "A town built round its bottle kilns: a Kiln Hall, a Supply, Menders, and chimneys everywhere.",
                   config: { services: { inn: 100, shop: 100, guild: 100, temple: 80 }, npcs: [ 5, 8 ], stock: [ 9, 14 ], buildings: [ 12, 16 ],
                             tables: %w[town_names given_names hooks townsfolk_memories townsfolk_wishes service_names buildings kiln_stock] } },
      shed_village: { name: "Shed village", kind: "town", description: "Drying sheds and the people who live in them, out of the wind. A Menders' house; no Hall.",
                      config: { services: { inn: 100, shop: 70, guild: 0, temple: 100 }, npcs: [ 3, 5 ], stock: [ 6, 9 ], buildings: [ 8, 11 ],
                                tables: %w[town_names given_names hooks townsfolk_memories townsfolk_wishes service_names buildings village_stock] } },
      barge_town: { name: "Barge town", kind: "town", description: "Quays, slip tanks and barges. Everyone is covered in clay and talking.",
                    config: { services: { inn: 100, shop: 100, guild: 60, temple: 40 }, npcs: [ 4, 6 ], stock: [ 8, 12 ], buildings: [ 10, 14 ],
                              tables: %w[town_names given_names hooks townsfolk_memories townsfolk_wishes service_names buildings kiln_stock] } },
      clay_pits: { name: "Clay pits", kind: "dungeon", encounter_table: "pits",
                   description: "Galleries dug below the river, and the slip at the bottom. A good first dungeon.",
                   config: { rooms: [ 5, 7 ], loops: 1, locks: 1, decisions: { encounter: 4, event: 2, treasure: 2, fork: 1 }, boss: { pit_mother: 1 },
                             tables: %w[pit_names pit_rooms room_events forks treasure pit_locks] } },
      vaults: { name: "Misfire vaults", kind: "dungeon", encounter_table: "vaults",
                description: "Shelves of the misfired under a hill, and the Choir that keeps them company.",
                config: { rooms: [ 8, 11 ], loops: 2, locks: 2, decisions: { encounter: 5, event: 3, treasure: 2, fork: 2 }, boss: { choirmaster: 1, bone_china_doll: 2 },
                          tables: %w[vault_names vault_rooms room_events forks treasure vault_locks] } },
      saltworks: { name: "Flooded saltworks", kind: "dungeon", encounter_table: "estuary",
                   description: "Salt pans and glaze vats under a finger of water, and something that grew in them.",
                   config: { rooms: [ 7, 9 ], loops: 1, locks: 1, decisions: { encounter: 4, event: 3, treasure: 2, fork: 1 }, boss: { salt_wyrm: 1 },
                             tables: %w[works_names works_rooms room_events forks treasure works_locks] } },
      cold_kiln: { name: "The Great Kiln", kind: "dungeon", encounter_table: "kiln",
                   description: "A bottle kiln the size of a hill, cold for forty years, with the Guild's wardens inside and the Kilnmaster at the firemouth.",
                   config: { rooms: [ 9, 12 ], loops: 2, locks: 3, decisions: { encounter: 5, event: 3, treasure: 2, fork: 2 }, boss: { kiln_warden: 2 },
                             tables: %w[kiln_names kiln_rooms room_events forks treasure kiln_locks] } }
    }.freeze
  end
end
