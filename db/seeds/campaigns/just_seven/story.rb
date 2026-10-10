# frozen_string_literal: true

# The Just Seven's pressure and prep (Seeds::JustSeven): the omen clock, the
# Torso's siege, the secrets as chains of clues, the scenes the GM plays
# from the Stage, the flags kept as a checklist, and what's being said on
# the quays when the party arrives.
module Seeds
  module JustSeven
    # Signs 1 to 6 are the GM's to pace; Sign 7 is fixed to the Head's jaw.
    CLOCKS = [
      { name: "The Seven Signs", segments: 7, place: "The Steps", mode: "The chorus",
        impulse: "Two siblings sing to each other across the dead calm, and one of them is coming to finish an old fight.",
        portents: <<~PORTENTS,
          Sign 1: sea life floods the docks, the instant the Seer is thrown out.
          - Fish flop on the quay stones; crabs climb the mooring posts.
          Sign 2: the sea birds leave. One cormorant stays, on the sky bridge.
          - Not a gull anywhere. The quays are very quiet.
          - A single black bird on the sky bridge rail, looking out to sea.
          Sign 3: the harbour bells ring with no wind to ring them.
          - A bell rings, by itself, and then another answers it.
          Sign 4: lightning strikes the mausoleum on Founders' Hill.
          - Scorch marks up the dome, and nobody saw the storm.
          Sign 5: an earthquake, her first stirring. It sets back the funicular.
          - Cracked plaster everywhere, and every cup in the city rattled at once.
          Sign 6: the seven moons align, and a long tide goes out for days, exposing the Sword.
          - Ships sitting in the mud of the harbour, at an angle.
          Sign 7: the tide goes out completely. Fleet Crasher's answer to the chorus.
          - Something huge, coming over the seabed, from very far away.
        PORTENTS
        full_line: "The tide goes out all the way, and keeps going. Every bell in the city sings. Something is coming over the seabed, and it will be here within hours." },
      { name: "The siege", segments: 3, source: "The Cathedral",
        impulse: "The die-hards would rather cut the city's heart off than let the king's order stand.",
        portents: <<~PORTENTS,
          The water is shut off, valve by valve, in ritual order.
          - The cathedral fountains stop mid-splash.
          The power is cut. The cathedral goes dark.
          - The nightly glow on the hillside goes out.
          The "switch" is thrown. It only cuts the city's load: the surplus wakes the sacred beast.
        PORTENTS
        full_line: "The die-hards throw the switch. The city's load drops away, and the surplus pours into the sacred bull. It stands up." }
    ].freeze

    SECRETS = [
      # Nobody's to ask about: the king doesn't know it, and a question put the
      # moment he speaks would interrupt The coins.
      { key: "founder_pirate_king",
        body: "The city's holy founder was the Pirate King: a southern-sea raider who conquered his own home city with a captured kaiju " \
              "turned mecha, then retired, put her to sleep on the island slope and founded a city on top of her. The cult remembers a warrior-king who brought light.",
        steps: <<~STEPS },
          Why does a smoke lounge on a holy island fly a pirate's flag?
          The mainland tells of a Pirate King with a living ship. Nobody here thinks he ever came this way.
          The founder "brought light to a land of darkness": the lighthouse, the mirrors, the cathedral window. All his.
          The face on Founders' Hill is the Pirate King's flag.
        STEPS
      { key: "buried_mecha",
        body: "The city sits on a buried kaiju-mecha, reclined against the slope, face up, facing the sea, under the infill. The districts are her body: " \
              "the dock and the dump her feet, the garden and the sky bridge her arms, the cathedral her heart, the dome her head, the lighthouse her sword.",
        steps: <<~STEPS },
          Why do the pipes under the waterline thump, slow and steady, like a pulse?
          A joint the size of a chapel under the airship dock, machined and oiled.
          The dump's middle is a foot: a heel, a sole, toes.
          The districts are named like a body: legs, arms, heart, head.
        STEPS
      { key: "the_plunder", npc: "The King", place: "The King's Garden",
        body: "The treasury was the Pirate King's raiding plunder. The grandfather king knew, spent it rebuilding after the attack, resealed the rest " \
              "under his garden and died without telling his grandson. The coins come from the ports the Pirate King raided.",
        steps: <<~STEPS },
          Why don't the official rebuilding numbers match what the city ever earned? | The King
          The collector says it was odd to find an old mainland coin for sale on this island.
          Coins in the garden's treasury: the same plain mainland type, minted in a dozen southern-sea ports.
        STEPS
      { key: "the_prince", npc: "The Swordsman",
        body: "Forty years ago Fleet Crasher came to finish the old fight and a hailstorm drove him off. The prince died in the attack while his " \
              "bodyguard, now the swordsman, failed him; the grandfather king panicked on a balcony, and the priests recast it as a holy sacrifice.",
        steps: <<~STEPS },
          What happened forty years ago, the night the prince died?
          A storm of hail, out of season, and something enormous in the bay that left when it came. | The Swordsman
          The old king wasn't praying on the balcony. He was frozen. | The Swordsman
        STEPS
      { key: "oracle_optics", npc: "The Duel-Master", place: "The Sky Bridge",
        body: "The sky bridge oracle is pure optics: a prism splits the light into seven bands and green always falls on the slit. Every verdict " \
              "the court ever certified meant nothing.",
        steps: <<~STEPS },
          Has the slit ever shone anything but green?
          Nobody has gone into the sacred chamber in living memory, not even the priests.
        STEPS
      { key: "kill_list", place: "The Sword",
        body: "The lighthouse is a fleet-targeting light. Its beam pointed at whichever city the Pirate King meant to raid next; the ring of city " \
              "names on the lamp matches the mint marks on the treasury coins. Nobody has set a target in centuries, so it sweeps.",
        steps: <<~STEPS },
          Why does the lighthouse sweep the sea, when every ship knows where the island is?
          The lamp's casing is engraved with a ring of city names, each with an angle.
        STEPS
      { key: "the_heart", place: "The Cathedral",
        body: "The cathedral's generator is her heart: chambers and valves with conduit grown around them, beating. The cult's sacred-heart " \
              "iconography was a real organ all along, and every light in the city is wired to it.",
        steps: <<~STEPS },
          What thumps under the Steps, slow and steady, in every pipe?
          The cistern under the cathedral carries the same beat.
          The die-hards think the generator's switch is only a civic power switch.
        STEPS
      { key: "the_song",
        body: "The dead calm is a song: the two kaiju calling and answering across the sea, his a challenge, hers a taunt, and it fills the " \
              "air where the wind should be. The Gnallix built a hail bomb after the last attack, for when he came back.",
        steps: <<~STEPS },
          Where did the wind go?
          The island and the sea are asking each other where the wind went. | The Harbor Guild
          The harbour bells ring in time with something nobody can hear.
        STEPS
      { key: "the_siblings",
        body: "The mecha is Swirl-Pool, an orca-like kaiju, and the one coming is Fleet Crasher, her dolphin-like brother. They are siblings who " \
              "hate each other. There is no reunion: she is eager to fight him, not to be saved.",
        steps: <<~STEPS }
          Whose memories are the masks showing?
          She was dragged from the water mid-fight, leaving another one like her behind.
          When his call came through the pipes, her heart raced, and every light in the city with it.
        STEPS
    ].freeze

    SCENES = [
      { name: "Cold open: The Pirate King", script: <<~SCRIPT },
        Narrator: A flag fills the frame: a grinning face, a crown askew. The Pirate King. Under it, a slow song, two voices, very far apart.
        Narrator: Pull back. It hangs over the bar of a smoke lounge called The Pirate King, and the room is having a wonderful time.
        Narrator: No wind for weeks. Every ship in harbour stranded, sails hanging. Nobody here is in any hurry.
        The Collector (happy): Pull up a chair. Nobody's going anywhere.
      SCRIPT
      { name: "The Seer", ending: "battle", encounter: { lounge_brawler: 3, mob_leader: 1 }, script: <<~SCRIPT },
        Narrator: The door bangs open. An old woman, soaked to the knee, eyes wide.
        The Seer (angry): An ancient hero rising from the old king's tomb!
        The Seer (angry): And you sit here drinking while the sea holds its breath! Your frivolity brought this!
        Mob Leader (angry): Somebody show the old crow out.
        Narrator: They throw her out into the street, laughing. The instant she hits the cobbles, the harbour heaves, and the docks fill with fish.
        Mob Leader (angry): She did that! Get her!
      SCRIPT
      { name: "The swordsman's lead", ending: "reveal", reveal: "The Airship Dock", script: <<~SCRIPT },
        Narrator: At the Seer's door, an old man in court clothes is already waiting.
        The Swordsman (worried): I heard. She's been right before, you know. People forget that.
        The Swordsman: You did well tonight. There's a demo at the Harbor Guild tomorrow, an engine, of all things. Be there. Keep your eyes open.
      SCRIPT
      { name: "The collector's boon", script: <<~SCRIPT },
        The Collector: I watched what you did for the old woman. I read the sky the same way she does, only I'm leaving.
        The Collector: Here. An old mainland coin. Plain as anything. Buying it here was odd, which is why I came.
        The Collector (happy): If you make it off this island, you'll be a rich man. Not as rich as me...
        Narrator: By morning his yacht is gone: no sails, no sound, and no wind to take it.
      SCRIPT
      { name: "The demo", script: <<~SCRIPT },
        The Inventor (happy): Citizens! No wind? No matter! Behold the engine that needs no sail!
        Narrator: It roars. It roars louder. It keeps getting louder.
        Narrator: The blast takes the inventor and half the dock wall. Under the Guild Hall, a black opening, breathing.
        The Swordsman (determined): Let them through. These ones are good. I'll vouch for them myself.
      SCRIPT
      { name: "The coins", script: <<~SCRIPT },
        The King: You found a ledger?
        Narrator: The party sets down a sack of coin: old, plain, minted in a dozen ports across the southern sea.
        The King (surprised): That's not a ledger.
        The King (worried): That's where the money went. And where it came from.
        The King (determined): Whatever you need, ask.
      SCRIPT
      { name: "The heart", script: <<~SCRIPT },
        Narrator: The power comes back on. The heart's hard, racing thump eases into something slow and calm, and the lights come up across the city.
        Narrator: Then, through the dead air and up the cistern pipes, a call from far out at sea.
        Narrator: The heart spikes, fast and hard. Every light in the city surges with it, all at once, where everyone can see.
      SCRIPT
      { name: "The jaw opens", script: <<~SCRIPT },
        Narrator: Seven beams of light cross the city and strike the dome.
        Narrator: The face on Founders' Hill opens its jaw. It is the Pirate King's flag, made of iron.
        Narrator: And it sings. Every pipe, bell and cistern in the city sings with it, deafening. Out past the Sword, the sea pulls back, and keeps going.
      SCRIPT
      { name: "Vision: Red", script: "Narrator: Through the mask: open water, endless and warm. Swimming, fast and free, for the joy of it." },
      { name: "Vision: Orange", script: "Narrator: Through the mask: a great ship, and the pleasure of rolling it over. Splinters, bubbles, and play." },
      { name: "Vision: Yellow", script: "Narrator: Through the mask: chains, heavy and cold, and a fury with nowhere to go." },
      { name: "Vision: Green", script: <<~SCRIPT },
        Narrator: Through the mask: a fight in the water, against another one like her, and then hooks, and ropes, and being dragged out.
        Narrator: He's left behind, thrashing, unable to follow. She's afraid.
      SCRIPT
      { name: "Vision: Indigo", script: "Narrator: Through the mask: being opened, and fitted, and closed. Brass where there was flesh. The feeling fades." },
      { name: "Vision: Blue", script: "Narrator: Through the mask: a city burning under her feet, at a pirate's command. Nothing. She feels nothing at all." },
      { name: "Vision: Violet", script: <<~SCRIPT }
        Narrator: Every mask at once, for everyone wearing one: rage. Pure rage, and longing to crush him.
        Narrator: And a name, hers, for the first time: Swirl-Pool.
      SCRIPT
    ].freeze

    # The GM's own state, as a checklist. Never shown to players.
    FLAGS = {
      "just_seven" => [ "yes", "The Just Seven's own lines on arriving and on a failed check ask for this and island (Seeds::JustSeven::GENERATOR_TABLES)." ],
      "island" => [ "yes", "Set while the party is on the island. Clear it, and the world's own lines come back." ],
      "masks_found" => [ "0", "Seven in all: Red, Orange, Yellow, Green, Indigo, Blue, Violet. Each mask's vision plays when it's taken." ],
      "combiner_prism" => [ "in the garden", "Left Arm, in a reverse-threaded mount. Carried to the Head's third-eye socket." ],
      "splitter_prism" => [ "on the sky bridge", "Right Arm chamber ceiling. Carried to the Torso's socket opposite the window." ],
      "beam" => [ "sweeping", "Set and locked on the cathedral at the Sword's twist; the splitter then makes seven true beams." ],
      "king" => [ "investigating", "Ally once the Left Arm coins are delivered; signs the Torso order once shown the dial-and-coins proof." ],
      "ending" => [ "", "Bind (keep the masks and pilot her) or Break (surrender them; she fights unrestrained, wrecking the city top-down)." ]
    }.freeze

    # Talk on the quays when the story starts.
    RUMOURS = [
      "The island and the sea are asking each other where the wind went.",
      "There's a coin dealer drinking in The Pirate King who came in on a boat with no sails.",
      "The engine man at the Harbor Guild says he'll make the wind unnecessary. Tomorrow, at the dock."
    ].freeze
  end
end
