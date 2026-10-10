# frozen_string_literal: true

# The island's map (Seeds::JustSeven): the city climbs the slope from the
# waterline to Founders' Hill, laid out as she lies under it, reclined and
# face up, feet in the sea. Legs at the bottom, arms either side of the
# Reaches, the cathedral at her heart, the dome on her head, and the Sword
# point-down offshore. Players read a place's description; its notes are the
# GM's. A dungeon's rooms are the five-room beats, in order: what the table
# hears on entering each (an event's text is said aloud, so it holds no
# secrets), then the twist past the guardian.
module Seeds
  module JustSeven
    PLACES = {
      "The Steps" => {
        kind: "town", x: 800, y: 760, visible: true, template: "island_city",
        description: "The waterline tier: quays, warehouses, boarding houses, and a smoke lounge called The Pirate King. " \
                     "No wind for weeks. Every ship in harbour is stranded with its sails hanging.",
        notes: "Act 1 starts in The Pirate King, a smoke lounge under the Pirate King's flag (a mainland legend; nobody here ties him to the founder). " \
               "Give the party real time in the room before the Seer bursts in: gossip about the dead air, stranded crews, the Harbor Guild's theory " \
               "(\"the island and the sea are asking each other where the wind went\"). The collector sits here, better dressed than anyone; " \
               "he answers what he's asked and volunteers nothing.\n\n" \
               "Scenes, in order: Cold open, The Seer (ends in the mob fight), The swordsman's lead, The collector's boon. Tick the Seven Signs " \
               "when the Seer is thrown out (Sign 1: sea life floods the docks).\n\nThe city's districts are vague architectural names; let " \
               "the party build the body map themselves. Nobody remembers what's under the infill.",
        modes: [ { name: "The chorus", line: "Every bell, pipe and cistern in the city is singing, and out past the Sword the sea is gone.",
                   description: "Sign 7: the jaw is open. Fleet Crasher makes landfall within hours." } ]
      },
      "The Airship Dock" => {
        kind: "dungeon", x: 560, y: 800, visible: false,
        description: "Under the Harbor Master's Guild Hall, where the airships used to tie up. Blown open by the inventor's demo.",
        notes: "LEFT LEG. Guardian: the Crab (Rock), Red Mask. Mask vision 1 (Red): swimming free. Joy and ease.\n\n" \
               "1 Entrance: the inventor's public rocket-engine demo; he dies in the blast that opens the dock (scene: The demo). The swordsman " \
               "clears the way (\"these guys are good\") and nominates the party. The investors will slander them as saboteurs: a duel grievance later.\n" \
               "2 Puzzle: a living, sphincter-like door. Opens to rhythmic pressure, heat or lubrication; clenches tighter against force or damage. " \
               "Disarm it with a check for one of those; forcing it is the trap going off.\n" \
               "3 Setback: chitin armour, beautiful, lying there. It locks on after five minutes' wear and comes off only when the Crab's mask " \
               "does. Greaves halve movement, a vambrace takes an arm, a helm blinds, a breastplate suffocates (three failures shatter the ribs: " \
               "half HP, once). Play the impairments as statuses or fiction; it's in the bag as Chitin Plate.\n" \
               "4 Climax: the Crab. Shelled, high defence; Pincer; Clamp holds someone fast: a fire blow on the Crab frees them (the engine does that); " \
               "rhythm or grease is a Try Something, and force only clenches it harder. Every third turn it Hardens (defence up, reflect). Below half its shell breaks: low defence, two pincers a turn, " \
               "no more Harden. Mask breaks: an ordinary crab, and all the locked chitin falls off at once.\n" \
               "5 Twist: a colossal, plainly machined ankle joint. The first proof something mechanical-biological lives under the city.",
        rooms: [
          { name: "The demo stage", decision: { kind: "event", text: "The inventor's rocket engine roars, and roars louder, and takes the dock wall with it. " \
                                                                      "Smoke, screaming, and a way in under the Guild Hall." } },
          { name: "The living door", decision: { kind: "trap", text: "A door of wet muscle that clenches when it's pushed. (hurt 15)" } },
          { name: "The shell armoury", decision: { kind: "treasure", item: "chitin_plate" } },
          { name: "The deep berth", decision: { kind: "boss", monsters: { crab: 1 } } }
        ],
        twist: [ { name: "The ankle", text: "A joint the size of a chapel, machined and oiled, older than the city. Something under the streets has ankles." } ]
      },
      "The Dump" => {
        kind: "dungeon", x: 1040, y: 800, visible: false,
        description: "The haunted dump at the waterline: heaps of junk nobody can name, and lights at night.",
        notes: "RIGHT LEG. Guardian: the Raccoon (Dark/Ground), Orange Mask. Mask vision 2 (Orange): happily sinking a large ship. " \
               "Playful; a willing predator.\n\n" \
               "1 Entrance: with the dock revealed as foot-shaped, someone notices the dump's centre matches. A local kid went in during the dock " \
               "chaos and never came back.\n" \
               "2 Puzzle: debris golems animate nightly and process to the foot, but never perform if watched. Learn and reproduce the " \
               "kabuki-clapper pattern (accelerating clicks, one hard click, a falling \"ooooh\") to open the foot, or lie still and pass as junk to be " \
               "hauled in. A wrong performance leaves the foot shut and the golems alerted (call a fight: Debris Golems).\n" \
               "3 Setback: inside, golems meditate by slowly spinning to gather karma. Spin along the whole way: an Agility check each stretch, or " \
               "fall Dizzy into the fight (weary, or confuse at the start of the battle; your call).\n" \
               "4 Climax: the Raccoon. Scratch; Pilfer takes an item from the party's bag into the hoard (it comes back when " \
               "the Raccoon falls; gear is the GM's to take by hand); Junk Toss telegraphed for everyone; Hide breaks target lock. Below half: more frantic, a wider Junk Avalanche. The kid " \
               "commentates every steal. Mask breaks: an ordinary raccoon; everything stolen resurfaces; the kid is fine, in a nest of trinkets.\n" \
               "5 Twist: the debris is plainly Gnallix-era failed prototypes. No further twist needed.",
        rooms: [
          { name: "The heaps", decision: { kind: "event", text: "Mountains of junk, and in the middle a shape like the dock's: a heel, a sole, toes. Small footprints lead in." } },
          { name: "The procession", decision: { kind: "trap", text: "Scrap golems walk to the foot by night, clicking, and never while watched. (hurt 10)" } },
          { name: "The spinning walk", decision: { kind: "trap", text: "Golems turning slowly in place, all the way down the passage. Spin with them or fall. (weary 15)" } },
          { name: "The hoard", decision: { kind: "boss", monsters: { raccoon: 1 } } }
        ],
        twist: [ { name: "The prototypes", text: "Under the hoard, the junk is all one make: seamless machines nobody on the island could build, every one a failure." } ]
      },
      "The Reaches" => {
        kind: "landmark", x: 800, y: 560, visible: true,
        description: "The second tier, up the funicular: terraces, the old king's walled garden, and the sky bridge where duels are fought.",
        notes: "The funicular gate opens once both legs are cleared (open the road from The Steps). The swordsman then introduces the party to the " \
               "king, who sends them into the garden first. Undecided: whether a harder, guarded route bypasses the gate. Sign 5 (earthquake) sets " \
               "back the funicular repairs. The sky tram reaches only the Sword's outer pommel."
      },
      "The King's Garden" => {
        kind: "dungeon", x: 560, y: 520, visible: false,
        description: "The old king's private botanic garden, sealed since his decline. Where he went to reflect, people say.",
        notes: "LEFT ARM. Guardian: the Orchid Mantis (Bug; Grass while it's still an orchid), Yellow Mask. Combiner prism. Mask vision 3 (Yellow): captured in " \
               "chains. Anger.\n\n" \
               "1 Entrance: the king sends them on a hunch that the funding gap traces here, hoping for a ledger. He doesn't know what's hidden.\n" \
               "2 Puzzle: an ornate tool shed holds the old king's bonsai tools, hung with care (his secret hobby), enough for everyone. The vines " \
               "drag the careless toward carnivorous plants; they know the king's tools. Careful, deliberate pruning passes cleanly (disarm); " \
               "hacking, forcing or bare hands anger them (it goes off).\n" \
               "3 Setback: deep in the vines something gleams: the combiner prism, already there for reasons nobody knows. The Mantis just uses " \
               "the spot as a lure. Reaching for it springs the ambush straight into the fight.\n" \
               "4 Climax: the Orchid Mantis. It starts as A Striking Orchid; the first hit breaks the illusion. Riposte answers a blow up close before it " \
               "lands: half the time, then three times in four, then every time across its molts. Spells and shots from range get no answer. Lure is telegraphed. " \
               "Molts at two-thirds and one-third make it more ornate, not more menacing. Mid-fight, a look into the prism shows a coin-filled " \
               "room elsewhere in the garden.\n" \
               "5 Twist: unscrewing the prism (reverse-threaded) opens the way to the treasury, mostly emptied by the grandfather. The coins " \
               "trace to many southern-sea ports, the same type as the collector's coin. The party carries them to the king: a ledger expected, " \
               "plunder delivered (scene: The coins). He becomes an ally.",
        rooms: [
          { name: "The tool shed", decision: { kind: "event", text: "An ornate shed of tools for pruning tiny trees, every one hung with care. Beyond it, the vines are moving." } },
          { name: "The vine walk", decision: { kind: "trap", text: "Vines that drag the careless toward mouths that bloom. (hurt 20)" } },
          { name: "The gleam", decision: { kind: "event", text: "Deep in the vines something gleams: a prism, set in a threaded mount, beside a striking orchid." } },
          { name: "The orchid bed", decision: { kind: "boss", monsters: { orchid_bloom: 1 } } }
        ],
        twist: [ { name: "The treasury", decision: { kind: "treasure", gil: 600 } } ]
      },
      "The Sky Bridge" => {
        kind: "dungeon", x: 1040, y: 520, visible: false,
        description: "The sky bridge where sanctioned judicial duels settle grievances, and the sacred chamber at its far end.",
        notes: "RIGHT ARM. Guardian: the Cormorant (Flying), Green Mask. Splitter prism. Mask vision 4 (Green): dragged out of the " \
               "water mid-fight, leaving the other kaiju behind. Fear.\n\n" \
               "The chamber's splitter prism casts seven bands; green always falls on the slit the duel-master opens to certify a verdict.\n" \
               "1 Entrance: a court-recognised grievance is needed. A duellist may bring a second, so anyone suited can fight. More than six in " \
               "the party need more grievances. Ready-made: the Mob Leader (\"I'd win a fair fight\"), the Investors (slander: saboteurs), and a " \
               "priest calling them \"lying upstart rascals\", who is the Duel-Master.\n" \
               "2 Puzzle: win the duels. Use the duel at the table (Fight control: challenge the cast member).\n" \
               "3 Setback: the Duel-Master knows the slit is always green but not why. He refuses entry and accuses them of cheating: a new " \
               "grievance. Challenged, he can't refuse without exposing the oracle (refusing makes him a coward). He can't open the slit on his own " \
               "case, so the swordsman does: green, as always. He can't protest without confirming he knew.\n" \
               "4 Climax: opening the chamber door wakes the Cormorant (he always knew; it's why he never went in). Hooked Bill on whoever hit it " \
               "last; Circle takes it up out of reach of blows for two turns (a Ranger's reach or a spell still finds it); Dive is telegraphed " \
               "on whoever hit it last, and goes for whoever has hit it last when it drops (land a hit first to redirect). A missed Dive grounds " \
               "it for a turn. Wing Spread: the first " \
               "real wind in weeks, uncommented. Below half: more Dive and Circle.\n" \
               "5 Twist: testing the splitter proves the oracle was pure, unchanging optics. The court's legitimising ritual means nothing. The " \
               "Cormorant flies out through the slit toward the sea (Sign 2's holdout).",
        rooms: [
          { name: "The bridge court", decision: { kind: "event", text: "The sky bridge, with a court at either end. To cross, you need a grievance the court recognises." } },
          { name: "The duelling ground", decision: { kind: "event", text: "Chalk lines, a crowd, a bell. Grievances are settled here, one against one." } },
          { name: "The oracle slit", decision: { kind: "event", text: "A narrow slit in the chamber wall, and the priest who opens it after every duel. It shines green." } },
          { name: "The sacred chamber", decision: { kind: "boss", monsters: { cormorant: 1 } } }
        ],
        twist: [ { name: "The splitter", text: "A prism screwed into the ceiling splits the light into seven bands, and green always lands on the slit. Always." } ]
      },
      "The Sword" => {
        kind: "dungeon", x: 260, y: 640, visible: true,
        description: "Offshore, point-down in the seabed: a hilt and crossguard for piers, and a lamp in the pommel the city calls its lighthouse.",
        notes: "THE SWORD. Guardian: the Fire-bellied Toad (Fire/Water), Indigo Mask. Mask vision 5 (Indigo): being mechanised. Emotion fades.\n\n" \
               "Clue in: the Left Arm coins carry plain provenance and mint-city marks. The lamp's casing has an engraved ring of city names with " \
               "angles, and they match the coins' mint cities exactly. The road opens with Sign 6's long tide (switch the mode on).\n" \
               "1 Entrance: the long tide strands ships in the mud and exposes a hatch in the blade.\n" \
               "2 Puzzle: no stairs, an old flood-ballast lift. Work the ballast valves (a gauge by the hatch), climb the fuller groove on old " \
               "rigging, or hand-crank the winch. Brute strength does nothing.\n" \
               "3 Setback: three fights under rising water, a stage each. A fight that runs long pushes the water up a stage early. Ankle-deep: " \
               "fire weakened, moray eels that bite and hide. Waist-deep: everyone slower, a barnacle crust (thunder is the clean answer). " \
               "Chest-deep: thunder hits the whole party and a small drowning tick each round; a giant octopus grabs and inks.\n" \
               "4 Climax: the Toad. Hot Skin burns whoever touches it: a blow up close, not a spell or a shot. Belly Flash is telegraphed (enough damage on the telegraph turn interrupts it " \
               "and stuns it: a GM call). Dial Spin knocks the targeting lamp around: a sweeping light each round until someone spends an " \
               "action to jam the dial. Below half, Tide Call: a three-turn flood countdown; at zero the water douses the lamp, hits everyone hard " \
               "and the toad gets a free turn. Break the mask first.\n" \
               "5 Twist: read the dial against the coins: a kill list. Then set and lock the beam on the city's own heart, the cathedral. The beam " \
               "stops sweeping; the cult reads it as a sign, raising pressure at the Torso. The steady light lets the splitter make seven clean " \
               "beams. Fleet Crasher does not follow it: it's only a lock.",
        modes: [ { name: "Long tide", line: "The sea has pulled back for days. The Sword stands in the mud, and there's a hatch in its blade.",
                   description: "Sign 6: the seven moons align, and the tide stays out for days." } ],
        rooms: [
          { name: "The hatch", decision: { kind: "event", text: "Across the stinking seabed, a hatch in the blade, sealed for centuries, crusted, and unplundered." } },
          { name: "The ballast lift", decision: { kind: "trap", text: "An old lift car on ballast tanks. Muscle won't move it. (hurt 10, 1)" } },
          { name: "Ankle-deep", decision: { kind: "encounter", monsters: { moray_eel: 3 } } },
          { name: "Waist-deep", decision: { kind: "encounter", monsters: { barnacle_swarm: 2 } } },
          { name: "Chest-deep", decision: { kind: "encounter", monsters: { giant_octopus: 1 } } },
          { name: "The lamp room", decision: { kind: "boss", monsters: { fire_bellied_toad: 1 } } }
        ],
        twist: [ { name: "The dial", text: "An engraved ring of city names, each with an angle, around the lamp. The beam used to point at the next one." } ]
      },
      "The Cathedral" => {
        kind: "dungeon", x: 800, y: 330, visible: true,
        description: "The royal cathedral on the third tier, the Heart of the City: a great stained-glass window, a cistern beneath, and the generator.",
        notes: "TORSO. False boss: the Mechanical Bull (Normal). True guardian: the Viper (Poison/Grass), " \
               "Blue Mask. Mask vision 6 (Blue): destroying a city at the Pirate King's command, her will emptied out. Flat. Play " \
               "it just before the capstone.\n\n" \
               "Entry: the party brings the dial-and-coins proof to the king, who signs an order opening the sanctum. The compliant cult stands " \
               "aside, devastated. Die-hards under the Duel-Master bar the sanctum and plan a reverse siege, cutting water and power: they think " \
               "it's a civic switch, not a heart. The swordsman knows a royal culvert into the cistern behind their lines. Tick the Siege clock about " \
               "once a room; the heart keeps beating through it, never at risk.\n" \
               "1 Entrance: the culvert. Plant the clue: the heartbeat thumping through the pipes.\n" \
               "2 Puzzle: the valves were closed in ritual order and won't be forced: persuade a compliant clergy member for the sequence, or read " \
               "the heartbeat through the pipes.\n" \
               "3 Setback: die-hards and the Duel-Master; meant non-lethal and comic, echoing the lounge mob. Lights out partway (Siege 2).\n" \
               "4 Climax: the Bull (Gore; telegraphed Stampede; Steam Vent; Overclock below half: acts twice), then with no rest the Viper out of " \
               "its cracked chest (Fangs poison whoever is hurt most; telegraphed Spore Mist; Coil holds someone; Venom Surge below half). Any " \
               "blow on the Viper tears a coiled ally free, and that costs them a tenth of their HP.\n" \
               "5 Twist: behind the bull, a reactor that is plainly a heart, beating with the thump felt in the Left Leg pipes since Act 1.\n" \
               "Capstone (scene: The heart): restore the city's power; the heart settles; then Fleet Crasher's challenge-call comes through the pipes " \
               "and the heart spikes, and every light in the city surges with it. Does she side with her brother? Mount the splitter in the " \
               "reverse-threaded socket opposite the window: with the Sword's beam locked, seven true beams.",
        modes: [ { name: "Siege", line: "The cathedral doors are barred from inside. Die-hards sing on the steps, and the fountains have stopped.",
                   description: "The die-hards' reverse siege: the water off, then the power, then the switch." } ],
        rooms: [
          { name: "The culvert", decision: { kind: "event", text: "An old royal culvert into the cistern, dark and dripping. Through the pipes, a slow thump, like a heartbeat." } },
          { name: "The ritual valves", decision: { kind: "trap", text: "Valves closed in a ritual order, and chained. Force them and the pipes kick back. (hurt 15)" } },
          { name: "The barred sanctum", decision: { kind: "encounter", monsters: { die_hard: 3 } } },
          { name: "The generator hall", decision: { kind: "boss", monsters: { mechanical_bull: 1 } } }
        ],
        twist: [ { name: "The heart", text: "Behind the cracked bull, the generator: chambers, valves, conduit grown around something alive, beating." } ]
      },
      "The Palace" => {
        kind: "landmark", x: 1040, y: 280, visible: true,
        description: "The king's palace on the Capital tier, below the dome.",
        notes: "The king: not young, decent, powerless; quietly investigating why the rebuilding numbers don't match revenue. Privately knows he " \
               "isn't divine and keeps the royal cult as a civic fiction. He never says so; it shows in deflection and never claiming a miracle. " \
               "Becomes an ally with the Left Arm coins (scene: The coins). Signs the order opening the Torso."
      },
      "Founders' Hill" => {
        kind: "dungeon", x: 800, y: 130, visible: true,
        description: "The hill and dome at the top of the city, over the founders' mausoleum. Its face looks out to sea.",
        notes: "HEAD. Guardian: Amethyst 7A (Ghost/Steel; weak to Fighting too, as the notes have it), Violet Mask, the only mask with a face. Mask vision 7: not a vision, a " \
               "broadcast to every mask-wearer, NPCs too, once the combiner is placed: pure rage, longing to crush her brother, and her name, " \
               "Swirl-Pool (scene: Vision: Violet).\n\n" \
               "A short continuous sprint, no rests, inside the window between the jaw opening and Fleet Crasher's landfall. Everything is " \
               "prepared before the jaw opens; nothing carries from here into the battle. Every room mentions the sea pulling back and something " \
               "coming over the seabed. No clock: Sign 7 is fixed to the jaw. No permission gate.\n" \
               "1 Entrance: the seven beams open the jaw in public view, the Pirate King's flag as a face, and the deafening citywide chorus " \
               "(scene: The jaw opens; switch on The Steps' chorus mode, fill the Signs). Die-hard remnants hold the hill in suicidal waves; the " \
               "party is strong by now and mows through. A power-fantasy capstone.\n" \
               "2 Setback: her unshielded rage bleeds through the walls: an overwhelming, competitive urge to attack each other. The cost is HP and " \
               "resources, never time. A sharp character may notice it isn't their own, and it's aimed at a sibling.\n" \
               "3 Climax: Amethyst 7A (he lives here: he's the boss). He fights for real: he thinks they've come to stop the mecha, and the tide " \
               "going out proves they're too late. Autocannon; Missile Lock telegraphed on a name (guard, heal, or redirect by hitting him first); " \
               "Laser Sweep hits everyone; Her Song every third turn confuses (her rage, not his power; it never escalates); Overcharge below " \
               "half: two actions a turn, wide open. Mask breaks: the minimech powers down and he steps out. Told Fleet Crasher is really coming, " \
               "he's an excited spectator. Whether he survives or holds a mask in the finale is yours.\n" \
               "4 Twist: the combiner into the third-eye socket (only once the Violet mask is taken: all seven colours accounted for).\n" \
               "5 Result: the same light lights her eyes. She's awake and ready to pilot, with no breather.\n\n" \
               "THE GIANT BATTLE is not built: the party crews her stations against Fleet Crasher (Dragon/Fairy in the notes; weak to Ice, Poison, " \
               "Steel). Open: stations, the empty-station rule, her own HP pool, his phases, the hail bomb, the Bind and Break endings. Masks: " \
               "seven total, at least two players; with fewer than seven players the rest go to the swordsman, then Amethyst 7A, then the king; " \
               "with fewer than four, each wears two (half masks).",
        rooms: [
          { name: "The jaw", decision: { kind: "event", text: "Seven beams strike the dome, and the face on the hill opens its jaw. It is the Pirate King's flag. And it sings." } },
          { name: "The hill", decision: { kind: "encounter", monsters: { die_hard: 4 } } },
          { name: "The rage", decision: { kind: "trap", text: "A rage comes through the walls: you want to hit the person next to you, very badly. (hurt 20, weary 20)" } },
          { name: "The sealed room", decision: { kind: "boss", monsters: { amethyst_7a: 1 } } }
        ],
        twist: [ { name: "The third eye", text: "A socket in the brow, reverse-threaded, waiting for a prism. Seven colours accounted for." },
                 { name: "Her eyes", text: "The light goes into her head, and out through her eyes. Under the whole city, something wakes." } ]
      }
    }.freeze

    # [from, to, attrs]. Three start shut, for the GM to open: the funicular
    # once both legs are cleared, the Sword's road with the long tide
    # (Sign 6), the hill when the jaw opens. What each says is the journey,
    # heard every time the party goes that way, so it's said as the road is
    # once it's open; why it's shut is in the places' notes.
    ROADS = [
      [ "The Steps", "The Airship Dock", { duration: 0 } ],
      [ "The Steps", "The Dump", { duration: 0 } ],
      [ "The Steps", "The Reaches", { duration: 1, state: "blocked",
                                      travel_event: "The funicular car creaks up the slope, past terraces of washing that hasn't moved in weeks." } ],
      [ "The Reaches", "The King's Garden", { duration: 0 } ],
      [ "The Reaches", "The Sky Bridge", { duration: 0 } ],
      [ "The Reaches", "The Cathedral", { duration: 1 } ],
      [ "The Cathedral", "The Palace", { duration: 0 } ],
      [ "The Cathedral", "Founders' Hill", { duration: 1, state: "blocked",
                                             travel_event: "Up the processional stair to the hill, every bell in the city still singing." } ],
      [ "The Steps", "The Sword", { duration: 1, state: "blocked",
                                    travel_event: "Out across the stinking seabed, past ships lying on their sides, to the blade." } ]
    ].freeze
  end
end
