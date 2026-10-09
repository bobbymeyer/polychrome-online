# frozen_string_literal: true

# The setting: Oda's places and roads, its people, and its trouble. (Seeds::Oda)
module Seeds
  module Oda
    # Noonbell, the first town with a road, is where every campaign starts.
    PLACES = {
      "Noonbell" => { kind: "town", template: "frontier_town", x: 420, y: 340, known: true, seed: 301,
                      description: "A frontier town at a river ford, built around the bell tower that rings for duels. At noon the street empties and everybody watches it from a window.",
                      notes: "Every campaign starts here. Sheriff Wade Ashdown is the Powder Company's man; he looks the other way at noon.",
                      activities: "Guard a powder wagon (Dawn, 2, money 30): Out to the flats and back before the heat.\n" \
                                  "Watch a duel under the bell (Noon, exp 15): Two people, a long silence, and then it's over.\n" \
                                  "Cards at the Long Noon (Night, rumour): The table talks more than the players.",
                      night_line: "Noonbell by night: the bell tower black against the stars, and a lamp in the sheriff's window till late." },
      "Saltpeter" => { kind: "town", template: "frontier_town", x: 650, y: 430, known: true, seed: 302,
                       description: "The powder town: refineries, quays and Company warehouses on the river. Everything smells of salt and sulphur.",
                       notes: "The Powder Company's office is here, and Overseer Marrow Vey runs the Deep Seam from it.",
                       activities: "Grind salt at the refinery (Dawn, Noon, 2, money 40): Hard on the lungs; the Company pays by the barrel.\n" \
                                   "Haggle on the quays (Dusk, money 25, rumour): Powder, pelts, gossip, by the crate.",
                       night_line: "Saltpeter by night: the refineries glow red, and the quays are busier than by day." },
      "Gearhold" => { kind: "town", template: "clock_town", x: 230, y: 230, known: true, seed: 303,
                      description: "A walled town of clockmakers and gunsmiths on a mesa top.",
                      activities: "Wind the town clock (Dawn, money 20): Three hundred steps up and a key as long as your arm.\n" \
                                  "Sit with a gunsmith (Noon, 2, exp 20): Springs, wheels and patience.",
                      night_line: "Gearhold by night: a thousand clocks ticking behind shutters." },
      "The Deep Seam" => { kind: "dungeon", template: "powder_mine", x: 700, y: 210, known: true, seed: 304,
                           description: "The Powder Company's deepest mine, following a seam of pure red salt down past where anyone should have stopped. The miners say it breathes.",
                           notes: "The Seam Giant waits at the deepest face. It's a long fight.",
                           past: { "was" => "mine", "founded" => 380, "family" => "Vey", "holder" => "Vey", "fall" => { "kind" => "waking", "ago" => 1 },
                                   "lost" => [ "The ninth shift" ], "edited" => true },
                           night_line: "The Deep Seam by night: the pithead lamps, and a glow from below that isn't lamps." },
      "Fort Cinder" => { kind: "dungeon", template: "bandit_fort", x: 120, y: 420, known: false, seed: 305,
                         description: "A stockade on a burnt bluff where the cowards go: everyone who refused a duel and couldn't stand the shame, armed and angry.",
                         past: { "was" => "fort", "founded" => 395, "family" => "Pike", "holder" => "Pike", "edited" => true },
                         lead: "The bandits on the west road come from a fort on a burnt bluff. They say everyone up there refused a duel once." },
      "The Drowned Belfry" => { kind: "dungeon", template: "drowned_belfry", x: 560, y: 600, known: false, seed: 306,
                                description: "A bell tower standing in the lake the Company's dam made. At noon, on still days, the bell rings under the water.",
                                past: { "was" => "belfry", "founded" => 300, "family" => "Bellweather", "holder" => "Bellweather",
                                        "fall" => { "kind" => "flood", "ago" => 20 }, "edited" => true },
                                lead: "Fishers on the dam lake swear the drowned belfry rings at noon. The old bellringer waited there for a duel when the water came." },
      "The Red Mesas" => { kind: "wilds", x: 520, y: 120, known: true,
                           description: "Flat-topped, red-sided, and endless. Hawks circle; things below them watch the hawks.",
                           activities: "Hunt the mesas (Dawn, 2, find 100): A long day, a clean shot, and a pelt." },
      "The Powder Flats" => { kind: "wilds", x: 800, y: 330, known: true,
                              description: "Where the seams come to the surface: crusted white and red and yellow, crunching underfoot, and very easy to set alight.",
                              activities: "Skim surface salt (Dawn, 2, find 120): A sack, a scraper, and never a naked flame." }
    }.freeze

    ROUTES = [
      [ "Noonbell", "Saltpeter", { state: "dangerous", encounters: "mesa_road", duration: 1 } ],
      [ "Noonbell", "Gearhold", { state: "open", duration: 2, travel_event: "Up the switchbacks to the mesa top, and the ticking starts before you see the walls." } ],
      [ "Noonbell", "The Red Mesas", { state: "dangerous", encounters: "mesa_road", duration: 1 } ],
      [ "Saltpeter", "The Deep Seam", { state: "dangerous", encounters: "powder_flats", duration: 1,
                                        travel_event: "Company wagons on the road, all going one way, and the ground warm underfoot." } ],
      [ "Saltpeter", "The Powder Flats", { state: "dangerous", encounters: "powder_flats", duration: 1 } ],
      [ "Saltpeter", "The Drowned Belfry", { state: "dangerous", encounters: "the_belfry", duration: 2 } ],
      [ "Gearhold", "Fort Cinder", { state: "dangerous", encounters: "mesa_road", duration: 1 } ],
      [ "The Red Mesas", "The Deep Seam", { state: "dangerous", encounters: "mesa_road", duration: 1 } ]
    ].freeze

    # Who Oda's trouble belongs to (World#world_figures): brought into a
    # campaign's cast, and, with a Bestiary entry, able to fight as it (and
    # to issue a challenge, Campaign::Duels).
    FIGURES = {
      "Silas Crane" => { title: "The Smiling Draw", monster: "smiling_draw", place: "Noonbell", colour: "orange",
                         blurb: "Forty-one duels, and he smiled through every one. Wants a forty-second.",
                         description: "A Courtsword who left the road to collect duels. He isn't cruel; he's bored, and a duel is the only thing that isn't. He'll challenge whoever the town talks about, and he never refuses. He has never lost, and he is beginning to want to." },
      "Marrow Vey" => { title: "Overseer of the Deep Seam", monster: "overseer", place: "Saltpeter", colour: "steel_grey",
                        blurb: "Runs the Powder Company's deepest mine. Digs where the old maps say not to.",
                        description: "Knows the giants are real: his ninth shift woke one. The Company wants more red salt than any seam can give, and he'd rather feed it miners than tell it no. He refuses every duel he's offered, and pays the shame price without blinking." },
      "Wade Ashdown" => { title: "Sheriff of Noonbell", place: "Noonbell", colour: "blue",
                          blurb: "Wears the star and the Company's coat over it.",
                          description: "Bought, and knows it. Rings the bell for Silas's duels himself and hates every one." }
    }.freeze

    # Oda's threads (World#world_fronts), dealt into every new campaign.
    FRONTS = {
      "What the seam woke" => {
        description: "The Powder Company has dug the Deep Seam too far, and the giants are waking.",
        clocks: [
          { name: "The seam goes deeper", segments: 8, public: true, triggers: %w[dawn], place: "Saltpeter", source: "The Deep Seam",
            impulse: "To dig red salt out of the deep, whatever it wakes",
            portents: <<~STEPS,
              The Company hires a new shift.
              - A notice at {place}: MINERS WANTED, DOUBLE PAY. | town
              The ground hums at night.
              - Cups rattle on the shelves at {place}, after dark. | town
              A miner comes up wrong.
              - A miner at {place} who won't stop staring at the floor. | town
              Something walks on the mesa at dusk.
              - A shadow on the mesa, too tall, going somewhere. | wilds
            STEPS
            full_line: "The Deep Seam splits open at dusk, and something the size of the bell tower climbs out of it and walks toward the river.",
            mode_name: "Giant at the gates", mode_line: "Saltpeter's refineries are dark. The Company men are on the walls, and there's a giant in the river.",
            mode_description: "A giant woke from the Deep Seam and came to Saltpeter. The outfitter is shut and everyone who can is leaving." }
        ],
        secrets: [
          { body: "The ninth shift didn't die in a cave-in. They woke a giant, and Vey sealed the gallery with them inside.", place: "The Deep Seam", figure: "Marrow Vey" }
        ]
      },
      "The forty-second duel" => {
        description: "Silas Crane, the Smiling Draw, wants a duel he can lose.",
        clocks: [
          { name: "The Smiling Draw's tally", segments: 4, public: true, triggers: %w[travel], place: "Noonbell", source: "Noonbell",
            impulse: "To find someone who can beat him",
            full_line: "The noon bell rings, and Silas Crane stands under it, smiling, and calls one of the party by name." }
        ],
        secrets: [
          { body: "Silas has never lost because he's never fought anyone who wasn't afraid of him. He'd lose to someone who isn't.", figure: "Silas Crane" }
        ]
      }
    }.freeze
  end
end
