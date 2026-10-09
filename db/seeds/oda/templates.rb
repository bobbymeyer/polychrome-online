# frozen_string_literal: true

# The Gazetteer: the kinds of town and dungeon in Oda. (Seeds::Oda)
module Seeds
  module Oda
    LOCATION_TEMPLATES = {
      frontier_town: { name: "Frontier town", kind: "town", description: "One street, a bell tower, a boarding house, and everybody watching the street at noon.",
                       config: { services: { inn: 100, shop: 100, guild: 100, temple: 70 }, npcs: [ 4, 7 ], stock: [ 9, 13 ], buildings: [ 10, 14 ],
                                 tables: %w[town_names given_names hooks townsfolk_memories townsfolk_wishes service_names buildings town_stock] } },
      clock_town: { name: "Clock town", kind: "town", description: "Walled, tidy and ticking: clockmakers, gunsmiths and the mask-maker's quarter.",
                    config: { services: { inn: 100, shop: 100, guild: 80, temple: 100 }, npcs: [ 5, 8 ], stock: [ 8, 12 ], buildings: [ 12, 16 ],
                              tables: %w[town_names given_names hooks townsfolk_memories townsfolk_wishes service_names buildings clock_stock] } },
      powder_mine: { name: "Powder mine", kind: "dungeon", encounter_table: "the_seam",
                     description: "Company galleries following a seam down, past where anyone should have stopped.",
                     config: { rooms: [ 6, 8 ], loops: 1, locks: 1, decisions: { encounter: 4, event: 2, treasure: 2, fork: 1, trap: 2 }, boss: { seam_giant: 1 },
                               tables: %w[mine_names mine_rooms room_events forks treasure locks traps] } },
      bandit_fort: { name: "Bandit fort", kind: "dungeon", encounter_table: "fort_cinder",
                     description: "A stockade on a bluff where the cowards who ran from their duels went to be somebody.",
                     config: { rooms: [ 5, 7 ], loops: 1, locks: 1, decisions: { encounter: 4, event: 2, treasure: 2, fork: 1, trap: 2 }, boss: { gunhand: 2 },
                               tables: %w[fort_names fort_rooms room_events forks treasure locks traps] } },
      drowned_belfry: { name: "Drowned belfry", kind: "dungeon", encounter_table: "the_belfry",
                        description: "A bell tower in a valley the dam flooded, and the duel it's still waiting for.",
                        config: { rooms: [ 5, 7 ], loops: 1, locks: 1, decisions: { encounter: 3, event: 3, treasure: 2, fork: 1 }, boss: { drowned_bellringer: 1 },
                                  tables: %w[belfry_names belfry_rooms room_events forks treasure locks] } }
    }.freeze
  end
end
