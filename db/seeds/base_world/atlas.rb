# frozen_string_literal: true

# The setting: its places and roads, its people, and its trouble. (Seeds::BaseWorld)
module Seeds
  module BaseWorld
    # The first town with a road is where a party starts. A place nobody
    # knows yet comes with its lead: the talk, started in the nearest town,
    # that puts it on the map when the party hears it.
    PLACES = {
      "Tule" => { kind: "town", template: "village", x: 420, y: 380, known: true, seed: 11,
                  description: "A market village at the crossroads, the kind of place stories start from." },
      "Goblin Hollow" => { kind: "dungeon", template: "goblin_cave", x: 250, y: 250, known: false, seed: 12,
                           description: "A cave in the hills above Tule. The goblins have been bold lately.",
                           lead: "Goblins have been coming down at night from a cave in the hills above the village. Three sheep gone this week." },
      "Greymere" => { kind: "wilds", x: 600, y: 230, known: true, description: "A grey lake in an old forest. Nobody fishes it now." },
      "Port Carwen" => { kind: "town", template: "port_town", x: 760, y: 500, known: true, seed: 13,
                         description: "Ships, sailors and more rumours than anyone can use." },
      "The Old Barrow" => { kind: "dungeon", template: "barrow", x: 720, y: 110, known: false, seed: 14,
                            description: "Graves dug deep into a hill past Greymere. Something down there won't stay buried.",
                            lead: "Nobody fishes Greymere any more. There are lights under the barrow hill past the lake again, like in grandmother's day." },
      "Stonepass" => { kind: "landmark", x: 900, y: 320, known: false,
                       description: "The one road over the mountains, and a warden's hut at the top.",
                       notes: "Snowed in, the warden says, and the road is blocked until the GM opens it: a thaw, a guide, or the warden's price.",
                       lead: "The pass is snowed in, they say. But a man in the harbour swears he came over it last week, and there was no snow at all." },
      "The Isle of Vell" => { kind: "wilds", x: 960, y: 640, known: false,
                              description: "An island of standing stones, a day's sail out. Nobody lives there, and yet the stones are kept clean.",
                              notes: "The crossing is blocked until the party pays Captain Maren (500 gil) and the GM opens the way.",
                              lead: "Captain Maren of the Gull's Wing will sail anyone out to the Isle of Vell, if they can pay what she asks." }
    }.freeze

    ROUTES = [
      [ "Tule", "Goblin Hollow", { state: "dangerous", encounters: "grasslands", duration: 1 } ],
      [ "Tule", "Greymere", { state: "dangerous", encounters: "old_forest", duration: 1 } ],
      [ "Tule", "Port Carwen", { state: "open", duration: 2, travel_event: "The coast road is busy and safe: carts, pilgrims, a tinker singing." } ],
      [ "Greymere", "The Old Barrow", { state: "dangerous", encounters: "old_forest", duration: 1 } ],
      [ "Port Carwen", "Stonepass", { state: "blocked", encounters: "mountain_pass", duration: 2,
                                      travel_event: "Snow to the knee, then to the waist, and then, at the warden's hut, none at all." } ],
      [ "Port Carwen", "The Isle of Vell", { state: "blocked", duration: 1,
                                             travel_event: "The Gull's Wing leans into a grey swell. Maren sings the whole way and won't say why." } ]
    ].freeze

    # Who the setting's trouble belongs to (World#world_figures): brought into
    # a campaign's cast, and able to fight as the monster named.
    FIGURES = {
      "Grol Tusk" => { title: "Chief of the Goblin Hollow goblins", monster: "goblin_chief", place: "Goblin Hollow",
                       blurb: "Bigger than a goblin should be, and wearing a hat that was a crown once.",
                       description: "Raids Tule for silver, not food: he's paid in grave-coin by something under the Barrow." },
      "Morrow" => { title: "The Barrow Lord", monster: "dark_mage", place: "The Old Barrow",
                    blurb: "Tule's reeve, a hundred years dead, and not finished.",
                    description: "Buried with the village charter. Whoever holds it rules Tule; he means to, again." }
    }.freeze

    # The setting's main thread (World#world_fronts), dealt into every new
    # campaign: the goblins are the symptom, the Barrow is the cause.
    FRONTS = {
      "The Barrow Lord's silver" => {
        description: "Something under the Barrow wants Tule back, and pays the goblins to soften it up.",
        clocks: [
          { name: "The goblins raid Tule", segments: 4, public: true, triggers: %w[dawn], place: "Tule", source: "Goblin Hollow",
            impulse: "To bleed Tule until it begs the Barrow for help",
            portents: <<~STEPS,
              Goblins steal from the outlying farms by night.
              - A trampled hedge, and a pig that isn't there any more. | !dungeon
              - Little muddy footprints across the road, all going the same way. | wilds
              Tule's farmers stop going out after dusk.
              - Shutters closed at {place} before the sun is down. | town
              - A farmer at {place} with a pitchfork by the door, and nobody's laughing. | town
              The goblins hit the mill, and someone is hurt.
              - Flour on the road, and blood in the flour.
              - A bandaged boy at {place}, and a crowd that wants someone to blame. | town
            STEPS
            full_line: "The goblins burn Tule's granary. The village will go hungry this winter.",
            mode_name: "Raided", mode_line: "Smoke over Tule: the granary is ash.", mode_description: "Boarded windows and short tempers." },
          { name: "The Barrow Lord wakes", segments: 6, public: false, triggers: %w[now_and_then], source: "The Old Barrow",
            impulse: "To take back what was buried with him",
            portents: <<~STEPS,
              The barrow's stones sweat in the cold.
              - A frost on the grass at {place} that doesn't lift at noon. | day
              Grave-coin turns up in Tule's market.
              - A silver coin in the change at {place}, old, cold, with a face nobody knows. | town
              The dogs won't go near the Greymere road.
              - Dogs at {place} whining at the north road, all at once. | town
              - The birds go quiet, all of them, for a moment. | wilds
              Lamps burn blue near the water.
              - A lamp at {place} burning blue, and nobody will look at it. | dark
              Something walks the shore at night.
              - Wet footprints coming up from the lake. Only coming up. | night
            STEPS
            full_line: "Greymere freezes over in a night, and the dead walk its shore." }
        ],
        secrets: [
          { body: "The goblins raid for silver, not food: something under the Barrow pays them in grave-coin.", place: "Goblin Hollow", figure: "Grol Tusk" },
          { body: "Morrow was Tule's reeve a hundred years ago, buried with the village charter. Whoever holds it rules Tule.",
            place: "The Old Barrow", figure: "Morrow" },
          { body: "The warden at Stonepass is paid to say the pass is snowed in.", place: "Stonepass" }
        ]
      }
    }.freeze
  end
end
