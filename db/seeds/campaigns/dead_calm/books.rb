# frozen_string_literal: true

# What Dead Calm adds to Oda's books (Seeds::DeadCalm): the guardians and
# their forms, the mooks, the moves they use, the seven plain masks, and the
# five-room dungeon the island's places are rolled from. Added like any
# setting's entries: only what's missing, never over a GM's edits.
#
# Bobby's notes give fiction, structure and boss behaviour; the numbers here
# are a first pass to tune at the table. The notes' types are mapped onto
# Oda's: Rock and Ground are Earth, Bug and Flying are Wind, Normal is
# Steel, Poison/Grass is Earth with a poison bite, Ghost/Steel is Steel.
# There is no Ice or Psychic in Oda.
module Seeds
  module DeadCalm
    extend Helpers

    ABILITIES = {
      # --- the lounge mob and the cult --------------------------------------------------------
      bottle_toss: { name: "Bottle Toss", kind: "skill", target: "random_enemy", mp_cost: 0, gesture: "lunge",
                     effects: [ { primitive: "physical", power: 50 } ], description: "A bottle, thrown with more feeling than aim." },
      heckle: { name: "Heckle", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "shake",
                effects: [ { primitive: "debuff", stat: "spr", amount: 20, duration: 2 } ], description: "Loud, personal and not even clever." },
      fervour: { name: "Fervour", kind: "skill", target: "self", mp_cost: 0, gesture: "bounce",
                 effects: [ { primitive: "buff", stat: "str", amount: 30, duration: 3 } ], description: "Screaming for the king, and meaning it." },
      for_the_king: { name: "For the King!", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                      effects: [ { primitive: "physical", power: 150, recoil: 30 } ], description: "A charge that doesn't plan on coming back." },
      censure: { name: "Censure", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                 effects: [ { primitive: "physical", power: 110 } ], description: "A ceremonial blade, used unceremoniously." },
      sermon: { name: "Sermon", kind: "magic", target: "all_enemies", mp_cost: 0, gesture: "shake",
                effects: [ { primitive: "status", kind: "silence", chance: 40, duration: 2 } ], description: "Long enough that nobody else gets a word in." },

      # --- the Crab (Left Leg) -------------------------------------------------------------------
      pincer: { name: "Pincer", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                effects: [ { primitive: "physical", power: 120 } ], description: "A claw the size of a door." },
      clamp: { name: "Clamp", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "shake",
               effects: [ { primitive: "physical", power: 70 }, { primitive: "status", kind: "stop", chance: 100, duration: 2 } ],
               description: "Caught, and squeezed. Heat, rhythm or grease opens the claw; force only tightens it." },
      harden: { name: "Harden", kind: "skill", target: "self", mp_cost: 0, gesture: "tint",
                effects: [ { primitive: "buff", stat: "def", amount: 100, duration: 2 }, { primitive: "status", kind: "reflect", duration: 2 } ],
                description: "The shell plates lock shut, and powder skips off them." },
      twin_pincer: { name: "Twin Pincer", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                     effects: [ { primitive: "physical", power: 100, hits: 2 } ], description: "Both claws, no more caution." },

      # --- the Raccoon (Right Leg) ---------------------------------------------------------------
      scratch: { name: "Scratch", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                 effects: [ { primitive: "physical", power: 110 } ], description: "Small hands, long nails." },
      pilfer: { name: "Pilfer", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "slide",
                effects: [ { primitive: "physical", power: 60 }, { primitive: "steal", chance: 70, boon: 1 } ],
                description: "Whatever's shiny, into the hoard." },
      junk_toss: { name: "Junk Toss", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "shake", charge: 1,
                   effects: [ { primitive: "physical", power: 70 } ], description: "An armful of failed machines, thrown at everyone." },
      junk_avalanche: { name: "Junk Avalanche", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "shake", charge: 1,
                        effects: [ { primitive: "physical", power: 95 } ], description: "The whole pile, at once." },
      debris_slam: { name: "Debris Slam", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                     effects: [ { primitive: "physical", power: 120 } ], description: "A fist of scrap on a body of scrap." },

      # --- the Orchid Mantis (Left Arm) ----------------------------------------------------------
      bloom_sway: { name: "Bloom Sway", kind: "skill", target: "self", mp_cost: 0, gesture: "float",
                    effects: [ { primitive: "buff", stat: "agi", amount: 30, duration: 3 } ], description: "Just a flower, moving in a wind there isn't." },
      raptorial_strike: { name: "Raptorial Strike", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                          effects: [ { primitive: "physical", power: 140 } ], description: "A grab and a slash, faster than the eye." },
      lure: { name: "Lure", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "flash", charge: 1,
              effects: [ { primitive: "physical", power: 230 } ], description: "It flares, too bright for a flower, and waits for someone to step closer." },
      riposte: { name: "Riposte", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                 effects: [ { primitive: "physical", power: 90 } ], description: "Its answer comes before the question has finished." },

      # --- the Cormorant (Right Arm) -------------------------------------------------------------
      hooked_bill: { name: "Hooked Bill", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                     effects: [ { primitive: "physical", power: 120, type: "wind" } ], description: "A fisher's bill, on whoever hit it last." },
      circle: { name: "Circle", kind: "skill", target: "self", mp_cost: 0, gesture: "float",
                effects: [ { primitive: "away", who: "self", duration: 2 } ], description: "Up into the rafters, out of a blade's reach. A shot still finds it." },
      dive: { name: "Dive", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge", charge: 1,
              effects: [ { primitive: "physical", power: 240, type: "wind" } ], description: "It names its mark, folds its wings, and drops." },
      wing_spread: { name: "Wing Spread", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "shake",
                     effects: [ { primitive: "elemental", type: "wind", power: 8 }, { primitive: "debuff", stat: "agi", amount: 25, duration: 2 } ],
                     description: "A gust. The first real wind anyone has felt in weeks." },
      preen: { name: "Preen", kind: "skill", target: "self", mp_cost: 0, gesture: "bounce",
               effects: [ { primitive: "buff", stat: "def", amount: 50, duration: 3 } ], description: "Feathers oiled and laid flat." },

      # --- the flooding blade (the Sword) --------------------------------------------------------
      ink: { name: "Ink", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "tint",
             effects: [ { primitive: "status", kind: "blind", chance: 60, duration: 3 } ], description: "The water goes black." },
      grab: { name: "Grab", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "shake",
              effects: [ { primitive: "physical", power: 80 }, { primitive: "status", kind: "stop", chance: 100, duration: 1 } ],
              description: "An arm from the dark water, and then it doesn't let go." },
      tongue_lash: { name: "Tongue Lash", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                     effects: [ { primitive: "physical", power: 120 } ], description: "Quick, wet and heavier than it looks." },
      hot_skin: { name: "Hot Skin", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "tint",
                  effects: [ { primitive: "status", kind: "burn", chance: 100, duration: 2 } ], description: "Touch it and you'll know." },
      belly_flash: { name: "Belly Flash", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "flash", charge: 1,
                     effects: [ { primitive: "elemental", type: "fire", power: 45 } ],
                     description: "It arches, shows a belly red as a forge, and then the forge opens." },
      dial_spin: { name: "Dial Spin", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "spin",
                   effects: [ { primitive: "elemental", type: "fire", power: 12 } ], description: "The lamp's dial knocked round: a sweeping beam across the room." },
      tide_call: { name: "Tide Call", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "shake", charge: 3,
                   effects: [ { primitive: "elemental", type: "water", power: 60 } ],
                   description: "It croaks, the Sword hums back, and the sea starts coming in." },

      # --- the mechanical bull and the Viper (Torso) ---------------------------------------------
      gore: { name: "Gore", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
              effects: [ { primitive: "physical", power: 140 } ], description: "Brass horns, and a lot of engine behind them." },
      stampede: { name: "Stampede", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "shake", charge: 1,
                  effects: [ { primitive: "physical", power: 100 } ], description: "It paws the floor, and then everyone is in the way." },
      steam_vent: { name: "Steam Vent", kind: "skill", target: "self", mp_cost: 0, gesture: "fade",
                    effects: [ { primitive: "buff", stat: "def", amount: 60, duration: 3 } ], description: "A scald of steam, and the plates close behind it." },
      overclock: { name: "Overclock", kind: "skill", target: "self", mp_cost: 0, gesture: "flash",
                   effects: [ { primitive: "status", kind: "haste", duration: 5 } ], description: "The lights flicker. It moves twice for every breath." },
      fangs: { name: "Fangs", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
               effects: [ { primitive: "physical", power: 100 }, { primitive: "status", kind: "poison", chance: 60, duration: 3 } ],
               description: "Always for whoever is bleeding most." },
      spore_mist: { name: "Spore Mist", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "tint", charge: 1,
                    effects: [ { primitive: "status", kind: "poison", chance: 70, duration: 3 } ], description: "A green breath that fills the chamber." },
      coil: { name: "Coil", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "shake",
              effects: [ { primitive: "physical", power: 60 }, { primitive: "status", kind: "stop", chance: 100, duration: 2 } ],
              description: "Wrapped, and squeezed. Strike the snake and the coils tear free, and that hurts too." },
      venom_surge: { name: "Venom Surge", kind: "skill", target: "self", mp_cost: 0, gesture: "flash",
                     effects: [ { primitive: "status", kind: "haste", duration: 5 } ], description: "It strikes twice before anyone has seen it strike once." },

      # --- Amethyst 7A (Head) --------------------------------------------------------------------
      autocannon: { name: "Autocannon", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "shake",
                    effects: [ { primitive: "physical", power: 45, hits: 3, type: "shot" } ], description: "A rapid burst at one target." },
      missile_lock: { name: "Missile Lock", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge", charge: 1,
                      effects: [ { primitive: "physical", power: 260, type: "shot" } ], description: "A reticle settles on someone. Next turn, it's a missile." },
      laser_sweep: { name: "Laser Sweep", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "flash",
                     effects: [ { primitive: "elemental", type: "fire", power: 35 } ], description: "A beam across the whole party. Nowhere to stand that it doesn't reach." },
      her_song: { name: "Her Song", kind: "magic", target: "all_enemies", mp_cost: 0, gesture: "shake",
                  effects: [ { primitive: "status", kind: "confuse", chance: 50, duration: 2 } ],
                  description: "Her taunt through the walls. Everyone in the room wants to hit their brother." },
      overcharge: { name: "Overcharge", kind: "skill", target: "self", mp_cost: 0, gesture: "flash",
                    effects: [ { primitive: "status", kind: "haste", duration: 5 }, { primitive: "debuff", stat: "def", amount: 50, duration: 5 } ],
                    description: "Vents heat from every seam: two actions a turn, and wide open." },

      # --- the seven masks' own moves (Battle::Masks) --------------------------------------------
      red_breaker: { name: "Red Breaker", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                     effects: [ { primitive: "physical", power: 170, type: "earth", pierce: 40 } ], description: "The Red Mask's: a blow that goes through a shell." },
      junk_storm: { name: "Junk Storm", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "shake",
                    effects: [ { primitive: "physical", power: 100, type: "earth" } ], description: "The Orange Mask's: everything nearby, thrown." },
      petal_cut: { name: "Petal Cut", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "spin",
                   effects: [ { primitive: "physical", power: 160, type: "wind" } ], description: "The Yellow Mask's: beautiful, and then it isn't." },
      stoop: { name: "Stoop", kind: "skill", target: "single_enemy", mp_cost: 0, reach: true, gesture: "lunge",
               effects: [ { primitive: "physical", power: 200, type: "wind" } ], description: "The Green Mask's: a dive from nowhere, onto anyone." },
      forge_belly: { name: "Forge Belly", kind: "magic", target: "all_enemies", mp_cost: 0, gesture: "flash",
                     effects: [ { primitive: "elemental", type: "fire", power: 40 } ], description: "The Indigo Mask's: the warning colour, worn as a weapon." },
      venom_tide: { name: "Venom Tide", kind: "magic", target: "all_enemies", mp_cost: 0, gesture: "tint",
                    effects: [ { primitive: "elemental", type: "water", power: 30 }, { primitive: "status", kind: "poison", chance: 50, duration: 3 } ],
                    description: "The Blue Mask's: a green-blue wave that stings." },
      third_eye: { name: "Third Eye", kind: "magic", target: "all_enemies", mp_cost: 0, gesture: "flash",
                   effects: [ { primitive: "elemental", type: "deep", power: 50 } ], description: "The Violet Mask's: a light from behind the face." }
    }.freeze

    ITEMS = {
      # The masks: plain colours, no faces (but the Violet's), each found on a guardian that wore it for ages.
      red_mask: { name: "Red Mask", category: "mask", price: 0, stats: { def: 3 }, mask: { type: "earth", duration: 3, abilities: %w[red_breaker] },
                  description: "A plain red mask, chitin-smooth. A crab wore it under the airship dock for longer than the city has stood." },
      orange_mask: { name: "Orange Mask", category: "mask", price: 0, stats: { agi: 2 }, mask: { type: "earth", duration: 3, abilities: %w[junk_storm] },
                     description: "A plain orange mask, scratched all over by small claws." },
      yellow_mask: { name: "Yellow Mask", category: "mask", price: 0, stats: { agi: 3 }, mask: { type: "wind", duration: 3, abilities: %w[petal_cut] },
                     description: "A plain yellow mask that smells, faintly and always, of orchids." },
      green_mask: { name: "Green Mask", category: "mask", price: 0, stats: { spr: 2 }, mask: { type: "wind", duration: 3, abilities: %w[stoop] },
                    description: "A plain green mask, the colour of the light that always comes through the slit." },
      indigo_mask: { name: "Indigo Mask", category: "mask", price: 0, stats: { mag: 2 }, mask: { type: "fire", duration: 3, abilities: %w[forge_belly] },
                     description: "A plain indigo mask, warm to the touch, and damp." },
      blue_mask: { name: "Blue Mask", category: "mask", price: 0, stats: { mdef: 3 }, mask: { type: "water", duration: 3, abilities: %w[venom_tide] },
                   description: "A plain blue mask, warm as a nest." },
      violet_mask: { name: "Violet Mask", category: "mask", price: 0, stats: { mag: 3 }, mask: { type: "deep", duration: 2, abilities: %w[third_eye] },
                     description: "The only one of the seven with a face: violet, calm, and watching." },

      # Treasure the story hands over.
      collectors_coin: { name: "Collector's Coin", category: "accessory", price: 0, stats: { agi: 1 },
                         description: "An old mainland coin, plain: no overstrike, no symbols. \"If you make it off this island, you'll be rich.\"" },
      chitin_plate: { name: "Chitin Plate", category: "heavy_armor", price: 0, stats: { def: 18 },
                       description: "Beautiful shell armour, just lying there. It fits perfectly. It fits a little too perfectly." }
    }.freeze

    MONSTERS = {
      # --- Act 1: the smoke lounge's mob (low lethality: nobody dies in a bar fight) ---------------
      lounge_brawler: { name: "Lounge Brawler", level: 2, stats: stats(max_hp: 70, str: 10, atk: 8, agi: 10, def: 3, mdef: 2),
                        base_type: "steel", exp: 20, gil: 15, abp: 1,
                        ai_script: [ { if: { chance: 30 }, use: "bottle_toss" }, { if: { chance: 20 }, use: "heckle" }, { use: "attack" } ],
                        drops: [ { item: "tonic", chance: 20 } ], description: "Wind-stranded, bored, three drinks past sensible." },
      mob_leader: { name: "Mob Leader", level: 3, stats: stats(max_hp: 140, str: 13, atk: 12, agi: 10, def: 5, mdef: 3),
                    base_type: "steel", exp: 40, gil: 40, abp: 2,
                    ai_script: [ { if: { chance: 30 }, use: "heckle" }, { use: "attack" } ],
                    description: "Big voice, bigger grudge. He'd win a fair fight. He says so, often." },

      # --- the cult and its duel-master ----------------------------------------------------------
      die_hard: { name: "Die-hard", level: 6, stats: stats(max_hp: 130, str: 17, atk: 15, agi: 12, def: 7, mdef: 5),
                  base_type: "steel", exp: 60, gil: 30, abp: 3,
                  ai_script: [ { if: { self_hp_below: 50 }, use: "for_the_king" }, { if: { chance: 25 }, use: "fervour", once: true }, { use: "attack" } ],
                  description: "Screaming for the king, who never asked for this." },
      duel_master: { name: "The Duel-Master", level: 8, boss: true, stats: stats(max_hp: 420, max_mp: 30, str: 20, mag: 16, atk: 20, agi: 14, def: 12, mdef: 12),
                     base_type: "steel", exp: 250, gil: 300, abp: 8,
                     ai_script: [ { if: { round_multiple: 3 }, use: "sermon", say: "Kneel, rascals, and hear what the light says." },
                                  { if: { chance: 40 }, use: "censure" }, { use: "attack" } ],
                     boss_line: "Lying upstart rascals. The light will judge you.",
                     description: "Certifies the sky bridge's verdicts by the colour through a slit. Knows it's always green. Doesn't know why." },
      investors_second: { name: "Investors' Second", level: 5, stats: stats(max_hp: 200, str: 18, atk: 18, agi: 16, def: 8, mdef: 5),
                          base_type: "shot", exp: 100, gil: 150, abp: 4, ai_script: [ { if: { chance: 40 }, use: "quickdraw" }, { use: "attack" } ],
                          description: "Hired by the inventor's backers to fight their slander in a duel. Paid either way." },

      # --- the Crab (Left Leg, Red Mask) ---------------------------------------------------------
      crab: { name: "Crab", level: 5, boss: true, stats: stats(max_hp: 600, str: 18, atk: 16, agi: 6, def: 22, mdef: 8),
              base_type: "earth", exp: 220, gil: 200, abp: 8, affinities: { "thunder" => "weak", "fire" => "weak" },
              ai_script: [ { if: { round_multiple: 3 }, use: "harden", say: "The shell plates grind and lock shut." },
                           { if: { chance: 30 }, use: "clamp" }, { use: "pincer" } ],
              phases: [ { hp_below: 50, becomes: "crab_frenzied", say: "Shell plates crack and fall away. Under them, soft meat, and fury." } ],
              drops: [ { item: "red_mask", chance: 100 } ], boss_line: "Something the size of a cart sidles out of the dock's dark, wearing a red mask.",
              description: "A shore crab grown monstrous under a red mask it found and wore for longer than anyone can say." },
      crab_frenzied: { name: "Crab (Frenzy)", level: 5, boss: true, stats: stats(max_hp: 600, str: 20, atk: 18, agi: 8, def: 8, mdef: 6),
                       base_type: "earth", exp: 220, gil: 200, abp: 8, affinities: { "thunder" => "weak", "fire" => "weak" },
                       ai_script: [ { if: { chance: 30 }, use: "clamp" }, { use: "twin_pincer" } ],
                       drops: [ { item: "red_mask", chance: 100 } ], description: "Shell broken, no more hiding: two pincers a turn." },

      # --- the Raccoon (Right Leg, Orange Mask) --------------------------------------------------
      debris_golem: { name: "Debris Golem", level: 5, stats: stats(max_hp: 150, str: 16, atk: 14, agi: 6, def: 14, mdef: 4),
                      base_type: "earth", exp: 60, gil: 20, abp: 2, affinities: { "thunder" => "weak" }, ai_script: [ { use: "debris_slam" } ],
                      description: "Junk that walks, at night, when nobody watches. Somebody watched." },
      raccoon: { name: "Raccoon", level: 6, boss: true, stats: stats(max_hp: 560, str: 16, atk: 15, agi: 26, def: 10, mdef: 10),
                 base_type: "earth", exp: 260, gil: 260, abp: 9, affinities: { "wind" => "weak" },
                 ai_script: [ { if: { round_multiple: 4 }, use: "hide", say: "It dives into the pile and is gone." },
                              { if: { round_multiple: 3 }, use: "junk_toss", say: "It scrabbles up the heap with an armful of scrap." },
                              { if: { chance: 40 }, use: "pilfer" }, { use: "scratch" } ],
                 phases: [ { hp_below: 50, becomes: "raccoon_frantic", say: "It chitters, frantic, and grabs at everything." } ],
                 drops: [ { item: "orange_mask", chance: 100 } ], boss_line: "On top of the hoard, wearing an orange mask: a raccoon. A very large raccoon.",
                 description: "A dump raccoon that found an orange mask among the prototypes, and kept it, and kept everything else." },
      raccoon_frantic: { name: "Raccoon (Frantic)", level: 6, boss: true, stats: stats(max_hp: 560, str: 17, atk: 16, agi: 30, def: 10, mdef: 10),
                         base_type: "earth", exp: 260, gil: 260, abp: 9, affinities: { "wind" => "weak" },
                         ai_script: [ { if: { round_multiple: 3 }, use: "junk_avalanche", say: "It heaves at the whole pile." },
                                      { if: { chance: 60 }, use: "pilfer" }, { use: "scratch" } ],
                         drops: [ { item: "orange_mask", chance: 100 } ], description: "Grabbing at everything shiny, faster and faster." },

      # --- the Orchid Mantis (Left Arm, Yellow Mask): an orchid until it's hit, then two molts -----
      orchid_bloom: { name: "A Striking Orchid", level: 7, boss: true, stats: stats(max_hp: 620, str: 19, atk: 18, agi: 30, def: 10, mdef: 12),
                      base_type: "wind", exp: 300, gil: 300, abp: 10, affinities: { "fire" => "weak" },
                      ai_script: [ { use: "bloom_sway" } ],
                      phases: [ { hp_below: 99, becomes: "orchid_mantis", say: "The orchid moves. It was never a flower." },
                                { hp_below: 66, becomes: "orchid_mantis_molted", say: "It molts, and comes out of its old skin more beautiful." },
                                { hp_below: 33, becomes: "orchid_mantis_full_bloom", say: "Another molt: every colour at once, and desperate." } ],
                      drops: [ { item: "yellow_mask", chance: 100 } ], boss_line: "Deep in the vines, a striking orchid, pink and white, and something yellow glinting behind it.",
                      description: "An orchid. Probably." },
      orchid_mantis: { name: "Orchid Mantis", level: 7, boss: true, stats: stats(max_hp: 620, str: 19, atk: 18, agi: 30, def: 10, mdef: 12),
                       base_type: "wind", exp: 300, gil: 300, abp: 10, affinities: { "fire" => "weak" },
                       ai_script: [ { when: "hit", if: { chance: 50 }, use: "riposte" },
                                    { if: { round_multiple: 3 }, use: "lure", say: "It flares more vivid than any flower, and waits for someone to come closer." },
                                    { use: "raptorial_strike" } ],
                       drops: [ { item: "yellow_mask", chance: 100 } ],
                       description: "A floral mimic under a yellow mask. Hit it up close and it answers first." },
      orchid_mantis_molted: { name: "Orchid Mantis (Molted)", level: 7, boss: true, stats: stats(max_hp: 620, str: 20, atk: 19, agi: 32, def: 10, mdef: 12),
                              base_type: "wind", exp: 300, gil: 300, abp: 10, affinities: { "fire" => "weak" },
                              ai_script: [ { when: "hit", if: { chance: 75 }, use: "riposte" },
                                           { if: { round_multiple: 3 }, use: "lure", say: "It flares, gold and pink, and waits." },
                                           { use: "raptorial_strike" } ],
                              drops: [ { item: "yellow_mask", chance: 100 } ], description: "More ornate, not more menacing. Quicker to answer." },
      orchid_mantis_full_bloom: { name: "Orchid Mantis (Full Bloom)", level: 7, boss: true,
                                  stats: stats(max_hp: 620, str: 21, atk: 20, agi: 34, def: 10, mdef: 12),
                                  base_type: "wind", exp: 300, gil: 300, abp: 10, affinities: { "fire" => "weak" },
                                  ai_script: [ { when: "hit", use: "riposte" },
                                               { if: { round_multiple: 2 }, use: "lure", say: "Every colour of the masks at once. Come closer." },
                                               { use: "raptorial_strike" } ],
                                  drops: [ { item: "yellow_mask", chance: 100 } ], description: "Beauty, escalating with desperation. It answers every blow." },

      # --- the Cormorant (Right Arm, Green Mask) -------------------------------------------------
      cormorant: { name: "Cormorant", level: 8, boss: true, stats: stats(max_hp: 640, str: 20, atk: 19, agi: 30, def: 12, mdef: 10),
                   base_type: "wind", exp: 340, gil: 320, abp: 11,
                   affinities: { "earth" => "weak", "thunder" => "weak", "steel" => "resist" },
                   ai_script: [ { if: { round_multiple: 4 }, use: "circle", say: "It beats up into the chamber's height, out of reach." },
                                { if: { round_multiple: 3 }, use: "dive", say: "It fixes one eye on whoever hit it last, and folds its wings." },
                                { if: { chance: 25 }, use: "wing_spread" }, { if: { chance: 15 }, use: "preen" }, { use: "hooked_bill" } ],
                   phases: [ { hp_below: 50, becomes: "cormorant_frenzied", say: "It shrieks and climbs, and the dives come faster." } ],
                   drops: [ { item: "green_mask", chance: 100 } ], boss_line: "The chamber door opens, and something black and green-masked unfolds from the rafters.",
                   description: "The one sea bird that stayed, guarding a prism nobody was allowed to touch." },
      cormorant_frenzied: { name: "Cormorant (Frenzy)", level: 8, boss: true, stats: stats(max_hp: 640, str: 21, atk: 20, agi: 32, def: 12, mdef: 10),
                            base_type: "wind", exp: 340, gil: 320, abp: 11,
                            affinities: { "earth" => "weak", "thunder" => "weak", "steel" => "resist" },
                            ai_script: [ { if: { round_multiple: 3 }, use: "circle", say: "Up again, out of reach." },
                                         { if: { round_multiple: 2 }, use: "dive", say: "It marks someone and drops." }, { use: "hooked_bill" } ],
                            drops: [ { item: "green_mask", chance: 100 } ], description: "Diving and circling, never still." },

      # --- the flooding blade (the Sword, Room 3) ------------------------------------------------
      moray_eel: { name: "Moray Eel", level: 7, stats: stats(max_hp: 120, str: 18, atk: 16, agi: 20, def: 6, mdef: 6),
                   base_type: "water", exp: 70, gil: 30, abp: 3, affinities: { "thunder" => "weak" },
                   ai_script: [ { if: { chance: 30 }, use: "hide" }, { use: "bite" } ], description: "Out of a rust hole, a bite, and back in." },
      barnacle_swarm: { name: "Barnacle Swarm", level: 7, stats: stats(max_hp: 200, str: 14, atk: 13, agi: 4, def: 30, mdef: 10),
                        base_type: "water", exp: 80, gil: 30, abp: 3, affinities: { "thunder" => "weak" },
                        ai_script: [ { use: "attack" } ], description: "A crust that moves. Steel bounces; a spark goes right through." },
      giant_octopus: { name: "Giant Octopus", level: 8, stats: stats(max_hp: 380, str: 18, atk: 16, agi: 14, def: 8, mdef: 10),
                       base_type: "water", exp: 160, gil: 80, abp: 5, affinities: { "thunder" => "weak" },
                       ai_script: [ { if: { round_multiple: 3 }, use: "ink" }, { if: { chance: 50 }, use: "grab" }, { use: "attack" } ],
                       description: "Chest-deep water, and something in it with too many arms." },

      # --- the Fire-bellied Toad (the Sword, Indigo Mask) ----------------------------------------
      fire_bellied_toad: { name: "Fire-bellied Toad", level: 9, boss: true, stats: stats(max_hp: 760, max_mp: 40, str: 20, mag: 22, atk: 19, agi: 14, def: 14, mdef: 14),
                           base_type: "fire", exp: 380, gil: 360, abp: 12, affinities: { "water" => "resist" },
                           ai_script: [ { when: "hit", use: "hot_skin" },
                                        { if: { round_multiple: 3 }, use: "belly_flash", say: "It arches its back and shows a belly red as a forge." },
                                        { if: { round_multiple: 4 }, use: "dial_spin", say: "It knocks the lamp's dial spinning." },
                                        { use: "tongue_lash" } ],
                           phases: [ { hp_below: 50, becomes: "fire_bellied_toad_tide", say: "It croaks, low. Far below, the Sword hums back." } ],
                           drops: [ { item: "indigo_mask", chance: 100 } ], boss_line: "Under the lamp, a toad as big as a boat, in an indigo mask, puffing up.",
                           description: "A fire-bellied toad that has worn an indigo mask in the lamp room since before the tide covered the door." },
      fire_bellied_toad_tide: { name: "Fire-bellied Toad (Tide Call)", level: 9, boss: true,
                                stats: stats(max_hp: 760, max_mp: 40, str: 20, mag: 22, atk: 19, agi: 14, def: 14, mdef: 14),
                                base_type: "fire", exp: 380, gil: 360, abp: 12, affinities: { "water" => "resist" },
                                ai_script: [ { when: "hit", use: "hot_skin" },
                                             { once: true, use: "tide_call", say: "The flood countdown starts: three turns until the sea comes in. Break the mask first." },
                                             { if: { round_multiple: 3 }, use: "belly_flash", say: "It arches again, glowing." }, { use: "tongue_lash" } ],
                                drops: [ { item: "indigo_mask", chance: 100 } ], description: "The water is coming." },

      # --- the mechanical bull, then the Viper inside it (Torso, Blue Mask) -----------------------
      mechanical_bull: { name: "Mechanical Bull", level: 10, boss: true, stats: stats(max_hp: 700, str: 24, atk: 22, agi: 10, def: 20, mdef: 12),
                         base_type: "steel", exp: 300, gil: 300, abp: 10, affinities: { "thunder" => "weak" }, status_immune: %w[poison sleep confuse],
                         ai_script: [ { if: { round_multiple: 3 }, use: "stampede", say: "It paws the floor and lowers its brass horns." },
                                      { if: { chance: 25 }, use: "steam_vent" }, { use: "gore" } ],
                         phases: [ { hp_below: 50, becomes: "mechanical_bull_overclocked", say: "Something inside it races. The lights flicker." },
                                   { hp_below: 8, becomes: "viper", restore: 100,
                                     say: "Its chest cracks open, and out of the warm dark beside the reactor comes a viper in a blue mask." } ],
                         drops: [ { item: "blue_mask", chance: 100 } ], boss_line: "The surplus power wakes the sacred beast. It was never sacred.",
                         description: "A Gnallix-built false bull, worshipped as a sacred beast by people who never looked inside it." },
      mechanical_bull_overclocked: { name: "Mechanical Bull (Overclock)", level: 10, boss: true,
                                     stats: stats(max_hp: 700, str: 24, atk: 22, agi: 12, def: 18, mdef: 12),
                                     base_type: "steel", exp: 300, gil: 300, abp: 10, affinities: { "thunder" => "weak" }, status_immune: %w[poison sleep confuse],
                                     ai_script: [ { once: true, use: "overclock" }, { if: { round_multiple: 3 }, use: "stampede", say: "It lowers its horns." },
                                                  { use: "gore" } ],
                                     drops: [ { item: "blue_mask", chance: 100 } ], description: "Acting twice, the lights flickering with it." },
      viper: { name: "Viper", level: 10, boss: true, stats: stats(max_hp: 650, max_mp: 30, str: 22, mag: 20, atk: 20, agi: 22, def: 12, mdef: 14),
               base_type: "earth", exp: 400, gil: 400, abp: 13, status_immune: %w[poison],
               affinities: { "fire" => "weak", "wind" => "weak", "water" => "resist", "thunder" => "resist", "earth" => "resist", "steel" => "resist" },
               ai_script: [ { if: { self_hp_below: 50 }, once: true, use: "venom_surge", say: "Its venom surges: it strikes twice before anyone sees it strike once." },
                            { if: { round_multiple: 4 }, use: "spore_mist", say: "It breathes out a green haze." },
                            { if: { chance: 30 }, use: "coil", target: "lowest_hp" }, { use: "fangs", target: "lowest_hp" } ],
               drops: [ { item: "blue_mask", chance: 100 } ],
               description: "The true guardian: it nested for centuries in the bull's warm chest, by the heart. It always goes for whoever is hurt most." },

      # --- Amethyst 7A (Head, Violet Mask): a Gnallix in a minimech -------------------------------
      amethyst_7a: { name: "Amethyst 7A", level: 12, boss: true, stats: stats(max_hp: 1000, max_mp: 60, str: 24, mag: 26, atk: 24, agi: 16, def: 20, mdef: 18),
                     base_type: "steel", exp: 600, gil: 500, abp: 15, status_immune: %w[poison sleep confuse berserk],
                     affinities: { "fire" => "weak", "earth" => "weak" },
                     ai_script: [ { if: { round_multiple: 3 }, use: "her_song", say: "Her taunt rings through the walls. It isn't his. He fights inside it, unbothered." },
                                  { if: { round_multiple: 4 }, use: "missile_lock", say: "A targeting reticle settles. Missile lock." },
                                  { if: { chance: 30 }, use: "laser_sweep" }, { use: "autocannon" } ],
                     phases: [ { hp_below: 50, becomes: "amethyst_7a_overcharged", say: "Heat vents from every seam of the minimech. It's wide open, and twice as fast." } ],
                     drops: [ { item: "violet_mask", chance: 100 } ],
                     description: "A Gnallix, sealed in the Head since the founding, a little mad from the quiet. Fascinated, never bitter." },
      amethyst_7a_overcharged: { name: "Amethyst 7A (Overcharge)", level: 12, boss: true,
                                 stats: stats(max_hp: 1000, max_mp: 60, str: 24, mag: 26, atk: 24, agi: 18, def: 20, mdef: 18),
                                 base_type: "steel", exp: 600, gil: 500, abp: 15, status_immune: %w[poison sleep confuse berserk],
                                 affinities: { "fire" => "weak", "earth" => "weak" },
                                 ai_script: [ { once: true, use: "overcharge" },
                                              { if: { round_multiple: 3 }, use: "her_song", say: "Her song again. Steady as a tide." },
                                              { if: { round_multiple: 4 }, use: "missile_lock", say: "Missile lock." }, { use: "autocannon" } ],
                                 drops: [ { item: "violet_mask", chance: 100 } ], description: "Two actions a turn, venting heat." }
    }.freeze

    # The island's own voice, so The Steps doesn't sound like a mesa town.
    # Its people, shops and buildings come from these through its template;
    # what the GM is offered on arriving and on a failed check comes from
    # the arrivals and complications rows, which ask for the campaign's
    # dead_calm and island flags (Seeds::DeadCalm::FLAGS) and so fit no
    # other campaign. Asking that much, they beat Oda's own rows
    # (Story::Matcher: the most specific wins).
    GENERATOR_TABLES = {
      island_hooks: { name: "Island hooks", kind: "hooks",
                      entries: texts("Captains a ship that hasn't moved in five weeks, and drinks like it.",
                                     "Sells wind charms by the dozen. None of them work. Business has never been better.",
                                     "Swears the harbour bells rang last night with nobody near them.",
                                     "Lost a nephew in the attack forty years ago and still lights a lamp for the prince.",
                                     "Owes the Harbor Guild a berth fee for a ship that can't leave.",
                                     "Has a coin from the mainland and keeps asking people where it came from.",
                                     "Won't go near {dungeon} after dark. Won't say why.",
                                     "Is selling passage off the island, for when the wind comes back. Cash now.",
                                     "Plays the duelling odds on the sky bridge, and has never once lost money on the priest's side.",
                                     "Hears a thump in the cistern pipes at night, slow, like breathing.") },
      island_memories: { name: "Island memories", kind: "memories",
                         entries: texts("I was a girl when the hail came. Stones the size of fists, out of a clear sky, and then the bay was empty.",
                                        "My grandfather said the founder came out of the dark with a light in his hand. That's all he'd say.",
                                        "I used to sail. I'd sail now, if there were anything to sail on.",
                                        "I watched the old king on his balcony the night the prince died. He didn't move. Not once.",
                                        "There used to be gulls. You don't notice gulls until there aren't any.") },
      island_wishes: { name: "Island wishes", kind: "wishes",
                       entries: texts("I want the wind back. That's all. Just the wind.", "I'd like to know what's under {dungeon}.",
                                      "I want to see the slit on the sky bridge show anything but green, once.") +
                                [ { text: "My lad took a fever with the stillness. A tonic would see him through.", item: "tonic" },
                                  { text: "Salt in my eyes from the dead fish on the quay. Anything for it?", item: "eyewash" } ] },
      island_service_names: { name: "Island service names", kind: "service_names",
                              entries: texts("The Pirate King", "The Slack Sail", service: "inn") + texts("The Chandlery", "Harbor Stores", service: "shop") +
                                       texts("The Harbor Guild Hall", service: "guild") + texts("The Seamen's Chapel", "The Lamp House", service: "temple") },
      island_buildings: { name: "Island buildings", kind: "buildings",
                          entries: [ { text: "Smoke lounge", service: "inn", width: 90, height: 80, roof: "flat" },
                                     { text: "Chandlery", service: "shop", width: 70, height: 70, roof: "peak" },
                                     { text: "Guild hall", service: "guild", width: 90, height: 110, roof: "dome" },
                                     { text: "Seamen's chapel", service: "temple", width: 60, height: 120, roof: "peak" },
                                     { text: "Net loft", width: 60, height: 60, roof: "peak", weight: 3 },
                                     { text: "Warehouse", width: 90, height: 60, roof: "flat", weight: 3 },
                                     { text: "Stair-street houses", width: 50, height: 70, roof: "flat", weight: 4 },
                                     { text: "Bell tower", width: 36, height: 140, roof: "peak" } ] },
      dead_calm_arrivals: { name: "Dead Calm arrivals", kind: "arrivals",
                            entries: [ { text: "{place}. Not a breath of wind; every sail in harbour hangs like washing.", when: "dead_calm, island, town" },
                                       { text: "{place} again. The quay cats don't even look up.", when: "dead_calm, island, town, visits >= 2" },
                                       { text: "{place} by night: the cathedral's glow on the hill, and the bells quiet, for now.", when: "dead_calm, island, town, dark" },
                                       { text: "{place}. The air doesn't move here either, and somewhere below, something thumps, slow.",
                                         when: "dead_calm, island, dungeon, first_visit" },
                                       { text: "{place} is quiet. Under it, the slow thump goes on.", when: "dead_calm, island, dungeon, cleared" },
                                       { text: "{place}. From up here the whole stranded harbour is laid out below, the sea flat as a plate.",
                                         when: "dead_calm, island, landmark" },
                                       { text: "The faithful glance at {place}'s great window and then away, as if it might glance back.",
                                         when: "dead_calm, island, dungeon, place = The Cathedral" },
                                       { text: "Out on the water, {place}'s lamp turns, and turns, sweeping a sea nobody can sail.",
                                         when: "dead_calm, island, dungeon, place = The Sword" },
                                       { text: "People on the quay find somewhere else to stand when {coward} passes.", when: "dead_calm, island, town, cowards >= 1" } ] },
      dead_calm_complications: { name: "Dead Calm complications", kind: "complications",
                                 entries: [ { text: "A bell rings somewhere, though nobody's touched it, and everyone turns to look.", when: "dead_calm, island, town" },
                                            { text: "The pipes shudder; something under the floor shifts its weight.", when: "dead_calm, island, dungeon", does: "ambush" },
                                            { text: "A berth fee, a fine from the Harbor Guild, a round for the stranded crews.", when: "dead_calm, island, town", does: "lose 30" },
                                            { text: "No wind, all day: the heat sits on everyone like a hand.", when: "dead_calm, island, field", does: "weary 20" } ] }
    }.freeze

    # Bobby's dungeons are five rooms (entrance, puzzle, setback, climax,
    # twist). A chain is rolled from this and its rooms pinned to the
    # story's (Seeds::DeadCalm#dungeon!): the twist, after the guardian,
    # is a room added off the boss's.
    LOCATION_TEMPLATES = {
      island_city: { name: "Island city", kind: "town",
                     description: "A city on stairs, from the quays to the dome: smoke lounges, chandlers, guild halls and a great many bells.",
                     config: { services: { inn: 100, shop: 100, guild: 100, temple: 100 }, npcs: [ 5, 8 ], stock: [ 8, 12 ], buildings: [ 12, 16 ],
                               tables: %w[town_names given_names island_hooks island_memories island_wishes island_service_names island_buildings
                                          clock_stock] } },
      five_rooms: { name: "Five-room dungeon", kind: "dungeon",
                    description: "Entrance, puzzle, setback, climax, twist: one way in, one guardian, and something learned on the far side.",
                    config: { rooms: [ 4, 6 ], loops: 0, locks: 0, decisions: { event: 1 },
                              tables: %w[mine_names mine_rooms room_events forks treasure locks traps] } }
    }.freeze
  end
end
