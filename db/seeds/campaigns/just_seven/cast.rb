# frozen_string_literal: true

# Who the GM speaks as in The Just Seven (Seeds::JustSeven). Their notes
# are the GM's. Someone with a Bestiary entry fights as it, and duels as it: the
# grievances on the sky bridge are with the Mob Leader, the Investors'
# Second and the Duel-Master. Amethyst 7A lives in the Head: he's who waits
# in its last room. The kaiju are nonverbal and aren't cast.
module Seeds
  module JustSeven
    CAST = {
      "The Seer" => {
        title: "Old prophet",
        description: "Right about the omen, wrong about the cause: she blames public frivolity. Her line: \"An ancient hero rising from the old " \
                     "king's tomb\" (ambiguous on purpose). As a child she prophesied \"the king will die\"; it came true for the prince, so the " \
                     "cult dismisses her as wrong. Thrown out of the lounge, mobbed, rescued and walked home by the party."
      },
      "The Swordsman" => {
        title: "Court swordsman, sixty and more",
        description: "The party's guide and ally. The grandfather king's bodyguard, then the prince's; failed to protect the prince in the attack " \
                     "forty years ago and has carried it since. Saw the grandfather panic on the balcony. Trusts the Seer. Vouches for the party, " \
                     "nominates them for the dock, opens the oracle slit as neutral witness on the duel-master's case, and knows the royal culvert " \
                     "into the cistern. Third in line for a spare mask, after the players."
      },
      "The King" => {
        title: "The current king, the prince's son",
        description: "Not young; a good kid by the swordsman's account. Powerless but decent. Knows only that the rebuilding numbers don't match " \
                     "revenue, and is quietly looking. Privately knows he isn't divine and keeps the royal cult going as a civic fiction; never " \
                     "says so, never claims a miracle. Becomes an ally when the party brings the Left Arm coins. Signs the order opening the Torso " \
                     "sanctum. Last in line for a spare mask."
      },
      "The Collector" => {
        title: "Travelling coin dealer",
        description: "In The Pirate King, dressed far better than the room. Friendly; answers real questions openly (his silent, sail-less Gnallix " \
                     "yacht with its seamless fittings, his coins, his read of the omens) and volunteers nothing. Having watched the party protect " \
                     "the Seer, he reads the omen right and leaves the island that night; the party never gets the yacht. Gives them the plain " \
                     "mainland coin first: buying it here was odd, which is why he came."
      },
      "The Inventor" => {
        title: "Showman of engines",
        description: "Tesla-like. His public rocket-engine demo blows open the airship dock and kills him (Left Leg, room 1). No lasting fallout " \
                     "but his investors' slander."
      },
      "The Kid" => {
        title: "Treasure hunter, age about ten",
        description: "Sneaked into the dump during the dock chaos and was added to the Raccoon's hoard, unharmed. Commentates the Raccoon fight, " \
                     "especially every steal."
      },
      "Mob Leader" => {
        title: "Regular at The Pirate King", monster: "mob_leader",
        description: "Led the lounge mob against the Seer and got humiliated by the party. Grumbles that he'd win a fair fight: a ready-made " \
                     "duel grievance on the sky bridge."
      },
      "The Investors' Second" => {
        title: "Hired duellist", monster: "investors_second",
        description: "Fights for the inventor's backers, who are publicly slandering the party as saboteurs of the machine: a ready-made duel " \
                     "grievance."
      },
      "The Duel-Master" => {
        title: "Priest of the royal cult", monster: "duel_master",
        description: "Calls the party \"lying upstart rascals\" in public while covertly orchestrating grievances against them, because he fears " \
                     "their influence. Knows the oracle slit is always green, not why. Refuses them the chamber after they win, accuses them of " \
                     "cheating, and is exposed in his own duel. Later leads the die-hards' siege of the Torso."
      },
      "Amethyst 7A" => {
        title: "Gnallix", monster: "amethyst_7a", place: "Founders' Hill",
        description: "Sealed in the Head \"until needed\" since the founding; a little crazy from the isolation. A von Braun: fascinated by the " \
                     "machine, indifferent to what it costs people. Assumes the party has come to destroy the mecha and fights for real. Told Fleet " \
                     "Crasher is really coming, he becomes an excited spectator, invested in the spectacle, not in either sibling. Gnallix are " \
                     "built, not born: immortal but for injury, fewer every year, named for a gem and a code. Second in line for a spare mask."
      }
    }.freeze
  end
end
