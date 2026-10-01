# frozen_string_literal: true

# The codex: the valley's lore, a players' side and the GM's. (Seeds::Greenware)
module Seeds
  module Greenware
    CODEX = {
      "The Firing" => {
        category: "Faith", public: true,
        body: "Everyone in the valley is clay, and clay is finished by fire. Fired, you are hard, lasting, and whatever you were when the " \
              "fire found you: a good potter stays a good potter, a cruel child a cruel child, for a hundred years. It is the end of growing " \
              "and the end of breaking. Most people want it; everyone fears it; the Guild schedules it. Since the Great Kiln went cold nobody " \
              "in Cone has been fired, and a whole generation has grown up soft.",
        gm_notes: "The Firing is real and works as described. The unfired age, heal, change and die; the fired do none of these. The lie is " \
                  "that the Guild knows what it's doing, and that the Kiln is safe to light."
      },
      "The Kilnmasters' Guild" => {
        category: "Faction", public: true,
        body: "Twelve families who keep the kilns, the books and the loading list. Fired young, all of them, and sure that what was good for " \
              "them is good for everyone. Their wardens keep the gates of Cone, and their First, Orrin Vask, keeps the Great Kiln's door.",
        gm_notes: "Vask has lost the vote. The Guild will light the Kiln with or without him, and three of the twelve want him in it first."
      },
      "The Menders" => {
        category: "Faction", public: true,
        body: "Those who mend the cracked with gold along the break, the old way. A Menders' house takes anyone, fired or not, and takes no " \
              "Guild money. Bisque's is the largest; Sister Weld keeps it.",
        gm_notes: "Menders are the valley's temple service: a raising for the KO'd. Sister Weld won't mend a fired person who cracks; she " \
                  "thinks a crack in the fired is a door, and she has been through one."
      },
      "The Unfired" => {
        category: "People", public: true,
        body: "Forty years of children never fired: the valley's soft generation. Mortal, able to change their minds and their trades, " \
              "looked down on and quietly envied. Most live in Bisque's sheds or work the pits at Slipway; the Guild calls them greenware.",
        gm_notes: "The player characters are unfired. That's why they have archetypes and can change them, and why the fired, who can't, " \
                  "both pity and resent them."
      },
      "Cones" => {
        category: "Custom", public: true,
        body: "Money. Little pyramids of glaze-clay, graded by the heat they bend at. A cone-six buys a meal; a cone-ten, a barge. The Guild " \
              "mints them in the small kilns and fires them: the only firing anyone has seen in forty years."
      },
      "Maker's marks" => {
        category: "Custom", public: true,
        body: "Every person carries their maker's mark on the heel: the family that dug and threw them. Marks are read the way faces are. An " \
              "unmarked heel is a scandal or a mystery, depending on who's looking."
      },
      "The Cold Kiln, forty years" => {
        category: "History", public: true,
        body: "The last firing of the Great Kiln was Cold Kiln 1, the year the count began. Something went wrong inside: the door was sealed " \
              "from without, the Kilnmasters came out grey, and Orrin Vask took the Guild the same week. The Second Kiln had already blown, " \
              "ninety years before, and made the Glass Flats. The valley has gone without a great firing since.",
        gm_notes: "The Kiln cracked along the crown. It held, barely. Hollis Grell saw it in the cones, and only Vask was told."
      },
      "The Valley of Cone" => {
        category: "Region", public: true,
        body: "A river valley between the Charcoal Woods and the estuary, made of clay and built of kilns. Cone sits in the middle under the " \
              "Great Kiln; Bisque's sheds lie west of it, Slipway and the Harrow pits downriver, and the Glass Flats shine to the east. " \
              "Barges carry clay down and salt and cones back up."
      },
      "Crackday singing" => {
        category: "Rumour", public: true,
        body: "On Crackday, when the week's kilns would have been cracked open, colliers in the eastern woods hear singing from under the hill. " \
              "The Guild says it's the wind in the Vaults' flues.",
        gm_notes: "It's the Choir, and it has a part written for whoever comes in."
      }
    }.freeze
  end
end
