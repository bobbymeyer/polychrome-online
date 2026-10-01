# frozen_string_literal: true

# The setting: the valley's places and roads, its people, and its trouble. (Seeds::Greenware)
module Seeds
  module Greenware
    # Cone, the first town with a road, is where every campaign starts. A
    # place nobody knows yet comes with its lead: the talk, started in the
    # nearest town, that puts it on the map when the party hears it. Things
    # to do are written in the calendar's words (Wedging, Throwing, Drying,
    # Cooling; Lightday, Crackday...).
    PLACES = {
      "Cone" => { kind: "town", template: "kiln_town", x: 480, y: 340, known: true, seed: 101,
                  description: "The kiln-city. Twelve bottle kilns stand round the Great Kiln like children round a cold hearth, and the Kilnmasters' Hall keeps the count of who has been fired and who is owed it.",
                  notes: "Every campaign starts here. The Guild's wardens take names at the gate; the unfired are let in, and watched.",
                  activities: "Wedge clay for the Hall (Wedging, money 15): Slam, fold, slam, before the yards open. The Hall pays in cone-sixes.\n" \
                              "Haul saggars in the Hall yards (Throwing, 2, money 30): Heavy, hot, and a warden counts you in and out.\n" \
                              "Sit the cone-reading (Drying, Lightday, exp 15): An old Firekeeper holds a bent cone to the light and says what it saw.\n" \
                              "Listen at the Loading Door (Cooling, rumour): The door is cold, and people still come to put a hand on it and talk.",
                  night_line: "Cone by night: twelve chimneys black against a clear sky, and only the Kilnmasters' lamps lit. The wardens walk in pairs." },
      "Bisque" => { kind: "town", template: "shed_village", x: 300, y: 420, known: true, seed: 102,
                    description: "A village of drying sheds where the unfired live, out of the wind. Racks of leather-hard pots and leather-hard people, waiting.",
                    notes: "No Kiln Hall. The Menders' house takes anyone. Sister Weld has a copy of the loading list.",
                    activities: "Turn the greenware (Wedging, Throwing, 2, money 20): Every pot turned so it dries even. Yours too, somebody says.\n" \
                                "Sister Weld's rounds (Drying, restore 25): She goes shed to shed with a wet sponge and a bag of gold leaf.\n" \
                                "Sit up with the sheds (Cooling, rumour): Somebody always talks, in the dark, when the wind gets into the racks.",
                    night_line: "Bisque by night: the sheds creak as they cool, and the unfired lie awake listening for the Kiln." },
      "Slipway" => { kind: "town", template: "barge_town", x: 700, y: 480, known: true, seed: 103,
                     description: "The barge town where Harrow clay is dug, slaked and shipped down the estuary. Everyone is covered in it.",
                     notes: "Foreman Dace Harrow runs the pits for the Guild and knows what's at the bottom.",
                     activities: "Dig a shift at the pit edge (Wedging, Throwing, 2, money 40): Shovel, barrow, and the slip that gets into everything.\n" \
                                 "Ride a barge down to the mouth (Throwing, 2, reveal): From the water you can see the whole lower valley.\n" \
                                 "Quayside haggling (Drying, money 25, rumour): Salt, clay and talk, by the sack.",
                     night_line: "Slipway by night: barges knock against the quay, and something large moves under the slip tanks." },
      "The Great Kiln" => { kind: "dungeon", template: "cold_kiln", x: 480, y: 200, known: true, seed: 104,
                            description: "A bottle kiln the size of a hill, cold for forty years. The Guild keeps its loading door sealed and its flues shuttered. Nobody has been inside since the last firing.",
                            notes: "Sealed: the road is blocked until the party has the Kilnmaster's tongs, or Hollis Grell's way in through the flues, or the Firing opens the door for everyone. Kilnmaster Vask waits in its boss room.",
                            past: { "was" => "kiln", "founded" => 160, "family" => "Vask", "holder" => "Vask", "fall" => { "kind" => "hush", "ago" => 40 },
                                    "lost" => [ "Eleven apprentices of the last firing" ], "edited" => true },
                            night_line: "The Great Kiln by night: the biggest dark in the valley, and a warden's lamp at the foot of the ramp." },
      "Clay Pits of Harrow" => { kind: "dungeon", template: "clay_pits", x: 180, y: 300, known: false, seed: 105,
                                 description: "The oldest clay pits in the valley, dug so deep the galleries run under the river. The slip at the bottom has learned to move.",
                                 past: { "was" => "pit", "founded" => 113, "family" => "Harrow", "holder" => "Harrow", "fall" => { "kind" => "slip", "ago" => 41 },
                                         "lost" => [ "Marl Harrow" ], "edited" => true },
                                 lead: "Something in the Harrow pits has been pulling diggers under. Slipway's foreman says it's the slip settling. The diggers say it has hands." },
      "The Misfire Vaults" => { kind: "dungeon", template: "vaults", x: 760, y: 160, known: false, seed: 106,
                                description: "Where the Guild shelves what came out of the fire wrong: cracked, slumped, half-glazed people, kept on the books as 'awaiting mending'. Nobody has been mended.",
                                past: { "was" => "vault", "founded" => 100, "family" => "Vask", "holder" => "Vask", "edited" => true },
                                lead: "The Guild says misfires are stored in the Vaults past the Charcoal Woods, shelved and quiet. The colliers say they hear singing from under the hill on Crackday." },
      "The Old Saltworks" => { kind: "dungeon", template: "saltworks", x: 840, y: 560, known: false, seed: 107,
                               description: "Salt-glaze works on the estuary, flooded and left. The pans crust white; the glaze vats went into the river, and the river hasn't been the same.",
                               past: { "was" => "saltworks", "founded" => 95, "family" => "Sherd", "holder" => "Sherd", "fall" => { "kind" => "flood", "ago" => 40 },
                                       "lost" => [ "Umber Sherd" ], "edited" => true },
                               lead: "The saltworks at the river mouth flooded the year the Kiln went cold. Barge folk say the pans still steam at night, and that whatever's in there pays in salt-glazed cones." },
      "The Glass Flats" => { kind: "wilds", x: 620, y: 260, known: true,
                             description: "Where the Second Kiln blew, ninety years ago. The ground vitrified for a mile; it rings underfoot and cuts anything soft. Salvagers work it in thick boots.",
                             activities: "Salvage glass (Throwing, 2, find 120): Thick boots, a sack, and the sound of your own feet." },
      "Charcoal Woods" => { kind: "wilds", x: 640, y: 120, known: true,
                            description: "The colliers' woods, cut and burnt in rotation for kiln fuel. Stacks smoulder under turf. The hounds that run here have ash in their coats.",
                            activities: "Watch a stack with the colliers (Cooling, rumour): They talk, once it's dark and the turf is steaming." },
      "Cone-Reader's Tower" => { kind: "landmark", x: 820, y: 320, known: false,
                                 description: "A tower on the edge of the Glass Flats where Hollis Grell reads heat from a mile off. He has not come down in forty years.",
                                 notes: "Hollis knows the Kiln cracked in its last firing, and that lighting it again will bring it down on Cone. He'll say so if the party brings him a cone from inside the Kiln, or talks him round (Reading, hard).",
                                 lead: "Hollis Grell, the last Cone-Reader, left the Hall the year the Kiln went cold and went up a tower on the Flats. They say he knows why it did." }
    }.freeze

    ROUTES = [
      [ "Cone", "Bisque", { state: "open", duration: 1, travel_event: "The shed road: carts of greenware under wet cloth, and nobody hurrying." } ],
      [ "Cone", "Slipway", { state: "dangerous", encounters: "towpath", duration: 2 } ],
      [ "Cone", "The Great Kiln", { state: "blocked", encounters: "kiln", duration: 1,
                                    travel_event: "Up the long ramp to the loading door. Guild lead over the seams, and a warden's hut beside it." } ],
      [ "Cone", "Charcoal Woods", { state: "dangerous", encounters: "charcoal_woods", duration: 1 } ],
      [ "Cone", "The Glass Flats", { state: "dangerous", encounters: "flats", duration: 1 } ],
      [ "Bisque", "Clay Pits of Harrow", { state: "dangerous", encounters: "pits", duration: 1 } ],
      [ "Slipway", "Clay Pits of Harrow", { state: "dangerous", encounters: "towpath", duration: 1 } ],
      [ "Slipway", "The Old Saltworks", { state: "dangerous", encounters: "estuary", duration: 1,
                                          travel_event: "Downriver, the water goes white at the edges." } ],
      [ "Slipway", "The Glass Flats", { state: "dangerous", encounters: "flats", duration: 1 } ],
      [ "Charcoal Woods", "The Misfire Vaults", { state: "dangerous", encounters: "charcoal_woods", duration: 1,
                                                  travel_event: "The colliers' track ends at a turf door in the hill." } ],
      [ "The Glass Flats", "Cone-Reader's Tower", { state: "dangerous", encounters: "flats", duration: 1,
                                                     travel_event: "Glass all the way, and the tower never seems closer until it is." } ]
    ].freeze

    # Who the valley's trouble belongs to (World#world_figures): brought into
    # a campaign's cast, and, with a Bestiary entry, able to fight as it.
    FIGURES = {
      "Kilnmaster Orrin Vask" => { title: "First of the Kilnmasters' Guild", monster: "kilnmaster", place: "The Great Kiln", colour: "orange",
                                   blurb: "Fired at eleven, and perfect since. Keeps the Guild's books and the Kiln's door, and means to open both.",
                                   description: "Never fired. The glaze is paint, touched up every Restday behind a locked door. He has kept the Kiln cold out of terror, not duty, and now the Guild has voted over him: if it is lit, he goes in first, by his own rule, and he knows it." },
      "The Pit Mother" => { title: "What the Harrow slip became", monster: "pit_mother", place: "Clay Pits of Harrow", colour: "wine_red",
                            blurb: "The diggers' word for whatever is at the bottom of the Harrow galleries. Big, patient, and getting bigger.",
                            description: "Marl Harrow, a digger, went into the slip after a child forty-one years ago and came up as all of it. She remembers the valley's children because she is what they were dug from. She wants them home." },
      "The Choirmaster" => { title: "Who keeps time in the Vaults", monster: "choirmaster", place: "The Misfire Vaults", colour: "greyish_green",
                             blurb: "The colliers hear singing under the hill on Crackday. Something keeps the time.",
                             description: "The first misfire: a Kilnmaster's son, slumped and half-glazed in the Great Kiln's first firing and shelved for a century. The Choir isn't suffering. It has become something, and it wants the Kiln lit so more voices come." },
      "Sister Weld" => { title: "Mender of Bisque", place: "Bisque", colour: "sun_yellow",
                         blurb: "Goes shed to shed with gold leaf and a wet sponge. Won't mend the fired; says they chose.",
                         description: "Fired young and badly: a crack down her back, gold-seamed by her own hand. She knows where the Vaults' shelf-lock key is because she was shelved there a year before she walked out. She copied the loading list for the wardens, and left three names off." },
      "Hollis Grell" => { title: "The last Cone-Reader", place: "Cone-Reader's Tower", colour: "steel_grey",
                          blurb: "Left the Hall the year the Kiln went cold. Reads heat from a mile off and hasn't come down.",
                          description: "He read the cones at the last firing and saw the Kiln crack along the crown. He told Vask. Vask sealed the door and struck his name from the Hall. He is ashamed he didn't say it louder." },
      "Foreman Dace Harrow" => { title: "Runs the Harrow pits for Slipway", place: "Slipway", colour: "blue",
                                 blurb: "Says the slip is settling. Pays the diggers' families well, and quickly.",
                                 description: "Marl Harrow's grandson. Knows what's at the bottom and keeps digging, because the Guild pays by the ton and the Firing needs clay." }
    }.freeze

    # The valley's main thread (World#world_fronts), dealt into every new
    # campaign: a public clock that fills on the first of Cone, twelve new
    # days after the story starts on 49 Green.
    FRONTS = {
      "The Firing Moon" => {
        description: "The Kilnmasters' Guild has voted to light the Great Kiln on the first of Cone, and every unfired soul in the valley is on the loading list.",
        clocks: [
          { name: "The Kiln is loaded", segments: 12, public: true, triggers: %w[dawn], place: "Cone", source: "The Great Kiln",
            full_line: "The first of Cone. The Great Kiln is lit, and smoke stands over the valley for the first time in forty years. The wardens go shed to shed with the loading list.",
            mode_name: "Firing", mode_line: "Cone glows. The Supply is shuttered, the yards are full, and the heat comes down the streets from the Kiln.",
            mode_description: "The Kiln is lit. Every shop is shut, the wardens are everywhere, and the unfired are being walked up the ramp." },
          { name: "The sheds empty", segments: 6, public: false, triggers: %w[now_and_then], source: "Bisque",
            full_line: "Bisque's drying sheds stand half empty. The wardens have been taking the unfired up early, 'to be ready'." }
        ],
        secrets: [
          { body: "The Great Kiln cracked along the crown in its last firing. Hollis Grell read it in the cones and told Vask; that is why the door was sealed. Lit again, it falls on Cone.",
            place: "The Great Kiln", figure: "Hollis Grell" },
          { body: "Kilnmaster Vask was never fired. His glaze is paint.", figure: "Kilnmaster Orrin Vask" },
          { body: "The Choir in the Vaults wants the Kiln lit as much as the Guild does. Every misfire is another voice.", place: "The Misfire Vaults", figure: "The Choirmaster" },
          { body: "The loading list is in Sister Weld's hand. She copied it for the wardens, and left three names off.", place: "Bisque", figure: "Sister Weld" }
        ]
      },
      "What the pits remember" => {
        description: "The Harrow slip has woken, and it is pulling the valley's children home.",
        clocks: [
          { name: "The Harrow galleries spread", segments: 4, public: true, triggers: %w[travel], place: "Bisque", source: "Clay Pits of Harrow",
            full_line: "The ground under Bisque goes soft. A drying shed leans, then sinks to its eaves.",
            mode_name: "Sinking", mode_line: "Bisque's sheds lean. There is slip in the lanes, and it is warm.",
            mode_description: "The pits have reached under the village. Sheds sink, the Menders' house is shut, and the unfired are moving out." }
        ],
        secrets: [
          { body: "The Pit Mother was Marl Harrow, a digger, who went into the slip after a child and came up as all of it.", place: "Clay Pits of Harrow", figure: "The Pit Mother" },
          { body: "Foreman Dace Harrow knows what is at the bottom of the pits. The Guild pays by the ton.", place: "Slipway", figure: "Foreman Dace Harrow" }
        ]
      }
    }.freeze
  end
end
