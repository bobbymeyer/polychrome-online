# frozen_string_literal: true

# The codex: Oda's lore, a players' side and the GM's. (Seeds::Oda)
module Seeds
  module Oda
    CODEX = {
      "Duels" => {
        category: "Custom", public: true,
        body: "Two people, one against one, three passes each. Anyone can challenge anyone, and anyone can refuse. Whoever refuses is a " \
              "coward, and everyone knows it: a coward has no place in this world. The only way back is to fight another duel and win it. " \
              "When both stand level at the end, it's satisfaction, and both walk away with their name.",
        gm_notes: "A duel is outside battle: three swings each on a meter, the mark moving and narrowing every round; you swing for the " \
                  "opponent (docs/ODA.md). Challenge someone from the Fight control; they answer at the table. A coward gets no " \
                  "payoff at a rest, and dearer prices for the whole party."
      },
      "Powder" => {
        category: "Craft", public: true,
        body: "Elemental salts ground from crystal seams: red for fire, blue for water, yellow for thunder, grey for earth, green for wind. " \
              "Measured into cartridges and paper charms and fired through rods, staves and barrels. A gun is a cheap, dumb caster; a Mancer " \
              "is the expensive, clever kind. Monks give it up altogether.",
        gm_notes: "MP is powder (the world's word). The five powders beat each other round a circle; steel is the plain type, shot goes " \
                  "through armour, and the deep is what the giants are made of."
      },
      "The Mancers" => {
        category: "People", public: true,
        body: "Specialists, each in one powder: a Firemancer knows fire the way a smith knows iron. A single measure, a spread, a double and the " \
              "top measure, which no resistance stops. When the matchup is bad, they load an ally's weapon instead.",
        gm_notes: "Same-type is on in Oda: a move of the user's own type is half again as strong."
      },
      "The Giants" => {
        category: "Danger", public: true,
        body: "Raw powder that stood up. They wake when a seam is dug too deep, and every wound makes them bigger. Steel and shot glance off.",
        gm_notes: "Giants have the giant trait and the Deep type."
      },
      "The Powder Company" => {
        category: "Faction", public: true,
        body: "Owns the seams, the refineries, the wagons and most of the sheriffs. Pays well, and buries quietly.",
        gm_notes: "Marrow Vey runs its deepest mine and knows exactly what his men woke."
      }
    }.freeze
  end
end
