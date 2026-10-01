# frozen_string_literal: true

# The Gazetteer: the kinds of town and dungeon. (Seeds::BaseWorld)
module Seeds
  module BaseWorld
    LOCATION_TEMPLATES = {
      village: { name: "Village", kind: "town", description: "A small town on the road: an inn, a shop, a handful of worried people.",
                 config: { services: { inn: 100, shop: 90, guild: 20, temple: 40 }, npcs: [ 3, 5 ], stock: [ 6, 9 ], buildings: [ 8, 11 ],
                           tables: %w[town_names given_names town_hooks townsfolk_memories townsfolk_wishes service_names buildings village_stock] } },
      port_town: { name: "Port town", kind: "town", description: "Busy, crowded, full of rumours from the sea.",
                   config: { services: { inn: 100, shop: 100, guild: 80, temple: 60 }, npcs: [ 5, 8 ], stock: [ 9, 14 ], buildings: [ 12, 16 ],
                             tables: %w[town_names given_names town_hooks townsfolk_memories townsfolk_wishes service_names buildings shop_stock] } },
      goblin_cave: { name: "Goblin cave", kind: "dungeon", encounter_table: "goblin_cave",
                     description: "A short, twisting cave. A good first dungeon.",
                     config: { rooms: [ 5, 7 ], loops: 1, locks: 1, decisions: { encounter: 4, event: 2, treasure: 2, fork: 1 }, boss: { goblin_chief: 1 },
                               tables: %w[cave_names rooms room_events forks treasure locks] } },
      barrow: { name: "Barrow", kind: "dungeon", encounter_table: "barrow",
                description: "Old graves dug deep into the hill, and something that won't stay buried.",
                config: { rooms: [ 8, 11 ], loops: 2, locks: 2, decisions: { encounter: 5, event: 3, treasure: 2, fork: 2 }, boss: { dark_mage: 1, zombie: 2 },
                          tables: %w[dungeon_names rooms room_events forks treasure locks] } }
    }.freeze
  end
end
