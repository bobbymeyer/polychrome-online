# frozen_string_literal: true

# The Giant Battle (Seeds::JustSeven): the party crews Swirl-Pool against
# her brother, Fleet Crasher. A battle, pure and simple: no endings to
# choose between.
#
# Her stations are her systems, each a Bestiary entry the crew fights as
# (Crew): Blade, Breath, Rigging, Drive, Sonar, Damage Control and
# Ordnance. Each archetype crews the station its own fantasy fits (CREW),
# so a Healer keeps healing, now as damage control. A station down is a
# system offline until Damage Control reboots it; she falls when every
# system is down. Fewer than seven at the table, and the cast's wearers
# crew the rest (the swordsman, Amethyst 7A, the king); fewer than four,
# and each player crews two.
#
# Both kaiju are Dragon/Fairy, as the notes have it: Ice, Poison and Steel
# find them. Fleet Crasher fights in three phases: sword and buckler, then
# from under the water (only a shot with the reach, or Sonar, finds him),
# then enraged. The hail bomb, the Gnallix's cloud-seeding answer to the
# old storm, is Ordnance's, once.
module Seeds
  module JustSeven
    extend Helpers

    STATION_ABILITIES = {
      # --- Blade (Courtsword, Soldier): the main strike -----------------------------------------
      great_cut: { name: "Great Cut", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                   effects: [ { primitive: "physical", power: 200 } ], description: "Her fin-blade, the length of a street, brought down." },
      hold_the_cut: { name: "Hold the Cut", kind: "skill", target: "self", mp_cost: 0, gesture: "tint",
                      effects: [ { primitive: "gather", kind: "sheathed" } ], description: "The blade drawn back and held, waiting for his sword to commit." },
      release_the_cut: { name: "Release the Cut", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                         effects: [ { primitive: "physical", power: 160, with: "sheathed", boost: 60 } ], description: "Everything held, at once." },
      blade_ready: { name: "Blade Ready", kind: "skill", target: "self", mp_cost: 6, gesture: "flash",
                     effects: [ { primitive: "status", kind: "iai", duration: 2 } ], description: "The first lunge that comes for her is cut before it lands." },

      # --- Breath (the mancers): her elemental output, through the neon stripes -----------------
      frost_stripe: { name: "Frost Stripe", kind: "magic", target: "single_enemy", mp_cost: 8, gesture: "flash",
                      effects: [ { primitive: "elemental", type: "ice", power: 30 }, { primitive: "debuff", stat: "agi", amount: 20, duration: 2 } ],
                      description: "Cold down the white stripes, and out. It slows what it touches." },
      venom_stripe: { name: "Venom Stripe", kind: "magic", target: "single_enemy", mp_cost: 8, gesture: "tint",
                      effects: [ { primitive: "elemental", type: "poison", power: 28 }, { primitive: "status", kind: "poison", chance: 60, duration: 3 } ],
                      description: "A green bloom from her stripes, and it stays in the water." },
      neon_breath: { name: "Neon Breath", kind: "magic", target: "single_enemy", mp_cost: 16, gesture: "flash",
                     effects: [ { primitive: "elemental", type: "fairy", power: 24 } ], description: "Every colour in her stripes, at once. His own kind of light." },

      # --- Rigging (Thief): grapples and lines ---------------------------------------------------
      grapple_line: { name: "Grapple Line", kind: "skill", target: "single_enemy", mp_cost: 6, gesture: "slide",
                      effects: [ { primitive: "grab", chance: 40, duration: 1 } ], description: "Cables round his bill: he's held a turn, if they hold." },
      strip_the_plate: { name: "Strip the Plate", kind: "skill", target: "single_enemy", mp_cost: 4, gesture: "slide",
                         effects: [ { primitive: "dispel" } ], description: "Hooks in the buckler's straps, and his guard comes away with it." },
      cable_whip: { name: "Cable Whip", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "spin",
                    effects: [ { primitive: "physical", power: 110, type: "steel" } ], description: "A steel hawser, swung." },

      # --- Drive (Monk): the core, burning her own hull ------------------------------------------
      build_steam: { name: "Build Steam", kind: "skill", target: "self", mp_cost: 0, gesture: "bounce",
                     effects: [ { primitive: "gather", kind: "chi", amount: 2 } ], description: "The core thumps faster. Every light in her flickers." },
      overdrive: { name: "Overdrive", kind: "skill", target: "single_enemy", mp_cost: 0, hp_cost: 8, gesture: "lunge",
                   effects: [ { primitive: "physical", power: 180, pierce: 50, with: "chi", boost: 40 } ],
                   description: "Everything the core has, through his plating, and some of her own hull with it." },
      drive_ram: { name: "Drive Ram", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                   effects: [ { primitive: "physical", power: 170 } ], description: "Her whole weight, shoulder first." },

      # --- Sonar (Magician): her voice, the song and the tempo -----------------------------------
      sonar_lance: { name: "Sonar Lance", kind: "magic", target: "single_enemy", mp_cost: 6, gesture: "shake",
                     effects: [ { primitive: "elemental", type: "psychic", power: 32 } ], description: "A note so loud it finds him wherever he's gone." },
      slow_tempo: { name: "Slow Tempo", kind: "magic", target: "single_enemy", mp_cost: 8, gesture: "shake",
                    effects: [ { primitive: "status", kind: "slow", chance: 70, duration: 3 } ], description: "Her song drags, and his rhythm drags with it." },
      quicken: { name: "Quicken", kind: "magic", target: "single_ally", mp_cost: 10, gesture: "bounce",
                 effects: [ { primitive: "status", kind: "haste", duration: 3 } ], description: "The tempo for one system doubles." },
      echo_wall: { name: "Echo Wall", kind: "magic", target: "single_ally", mp_cost: 10, gesture: "tint",
                   effects: [ { primitive: "status", kind: "reflect", duration: 3 } ], description: "A wall of sound: what he throws comes back to him." },

      # --- Damage Control (Healer, Bodyguard): repair and reboot ---------------------------------
      patch_hull: { name: "Patch Hull", kind: "magic", target: "single_ally", mp_cost: 6, gesture: "tint",
                    effects: [ { primitive: "heal", power: 40, triage: 50 } ], description: "Plates over the worst of it; the worse it is, the more goes on." },
      reboot: { name: "Reboot", kind: "magic", target: "single_ally", mp_cost: 18, gesture: "flash",
                effects: [ { primitive: "revive", fraction: 40 } ], description: "A system offline comes back up, coughing." },
      seal_bulkheads: { name: "Seal Bulkheads", kind: "skill", target: "all_allies", mp_cost: 12, gesture: "tint",
                        effects: [ { primitive: "buff", stat: "def", amount: 30, duration: 3 } ], description: "Every door in her shut at once." },
      take_the_blow: { name: "Take the Blow", kind: "skill", target: "self", mp_cost: 0, gesture: "shake",
                       effects: [ { primitive: "status", kind: "cover", duration: 2 }, { primitive: "buff", stat: "def", amount: 30, duration: 2 } ],
                       description: "Armour turned to meet him, so every blow meant for a system lands here." },

      # --- Ordnance (Ranger): missiles, drones and the hail bomb ---------------------------------
      missile_salvo: { name: "Missile Salvo", kind: "skill", target: "random_enemy", mp_cost: 6, reach: true, gesture: "shake",
                       effects: [ { primitive: "physical", power: 60, hits: 3, type: "steel" } ], description: "A rack of Gnallix missiles, down into the water or not." },
      drone_strike: { name: "Drone Strike", kind: "skill", target: "single_enemy", mp_cost: 0, reach: true, gesture: "lunge",
                      effects: [ { primitive: "physical", power: 100, type: "steel" } ], description: "A drone off her back, wherever he is." },
      hail_bomb: { name: "Hail Bomb", kind: "skill", target: "single_enemy", mp_cost: 40, reach: true, gesture: "flash",
                   effects: [ { primitive: "elemental", type: "ice", power: 70 }, { primitive: "status", kind: "stop", chance: 100, duration: 1 } ],
                   description: "The Gnallix's cloud-seeder, built after the old storm drove him off. One shot: hail out of a clear sky, and he stops." },

      # --- Fleet Crasher ---------------------------------------------------------------------------
      bill_slash: { name: "Bill Slash", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                    effects: [ { primitive: "physical", power: 260 } ], description: "The marlin bill, off his head and swung like a sword." },
      buckler_bash: { name: "Buckler Bash", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                      effects: [ { primitive: "physical", power: 170 }, { primitive: "status", kind: "paralyze", chance: 30, duration: 1 } ],
                      description: "The chest plate, held like a shield, driven in." },
      buckler_up: { name: "Buckler Up", kind: "skill", target: "self", mp_cost: 0, gesture: "tint",
                    effects: [ { primitive: "buff", stat: "def", amount: 60, duration: 3 } ], description: "The plate raised. Strip it, or go round it." },
      crashing_lunge: { name: "Crashing Lunge", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge", charge: 1, interrupt: 6,
                        effects: [ { primitive: "physical", power: 420 } ],
                        description: "He draws back the bill and fixes on a system. Enough damage first, and he flinches." },
      tail_wave: { name: "Tail Wave", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "shake",
                   effects: [ { primitive: "physical", power: 140 } ], description: "A slap of the tail, and the sea comes over all of her." },
      sound_dive: { name: "Sound Dive", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "float",
                    effects: [ { primitive: "away", who: "self", duration: 1, power: 400, aloft: 1 } ],
                    description: "Under, and gone: only a shot with the reach, or her sonar, finds him before he comes up beneath a system." },
      wave_crash: { name: "Wave Crash", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "shake",
                    effects: [ { primitive: "physical", power: 170 } ], description: "He breaches, and the whole bay comes down on her." },
      frenzy: { name: "Frenzy", kind: "skill", target: "self", mp_cost: 0, gesture: "flash",
                effects: [ { primitive: "status", kind: "haste", duration: 5 }, { primitive: "buff", stat: "str", amount: 30, duration: 5 } ],
                description: "No more sword-work. He just wants her gone." },
      bill_storm: { name: "Bill Storm", kind: "skill", target: "random_enemy", mp_cost: 0, gesture: "spin",
                    effects: [ { primitive: "physical", power: 140, hits: 3 } ], description: "The bill, everywhere, faster than she can turn." }
    }.freeze

    # A station: a system of hers, as the crew fight it. Its moves are the
    # ones its script uses (Monster#ability_slugs), so the script uses them
    # all: it's how a wearer from the cast crews it, on their own.
    def self.station(name, stats, script, description)
      { name: name, level: 13, stats: stats, base_type: "dragon", second_type: "fairy", exp: 0, gil: 0, abp: 0,
        status_immune: %w[confuse rage berserk sleep], ai_script: script, description: description }
    end

    STATIONS = {
      station_blade: station("Blade", stats(max_hp: 900, max_mp: 40, str: 55, atk: 52, def: 30, mdef: 18, agi: 22, spr: 14),
                             [ { once: true, use: "blade_ready" }, { if: { round_multiple: 3 }, use: "hold_the_cut" },
                               { if: { round_multiple: 4 }, use: "release_the_cut" }, { use: "great_cut" } ],
                             "Swirl-Pool's main strike: the fin-blade. Courtswords and Soldiers crew it."),
      station_breath: station("Breath", stats(max_hp: 760, max_mp: 90, mag: 42, str: 14, atk: 10, def: 18, mdef: 32, agi: 22, spr: 20),
                              [ { if: { round_multiple: 4 }, use: "neon_breath" }, { if: { chance: 50 }, use: "frost_stripe" }, { use: "venom_stripe" } ],
                              "Her elemental output, through the neon stripes. The mancers crew it."),
      station_rigging: station("Rigging", stats(max_hp: 800, max_mp: 50, str: 44, atk: 44, def: 22, mdef: 18, agi: 40, spr: 14),
                               [ { if: { round_multiple: 3 }, use: "strip_the_plate" }, { if: { chance: 30 }, use: "grapple_line" }, { use: "cable_whip" } ],
                               "Grapples, lines and hooks. Thieves crew it."),
      station_drive: station("Drive", stats(max_hp: 980, max_mp: 20, str: 58, atk: 48, def: 26, mdef: 14, agi: 20, spr: 14),
                             [ { if: { round_multiple: 3 }, use: "build_steam" }, { if: { round_multiple: 4 }, use: "overdrive" }, { use: "drive_ram" } ],
                             "Her core. Monks crew it, and it burns her own hull for its finishers."),
      station_sonar: station("Sonar", stats(max_hp: 780, max_mp: 90, mag: 50, str: 12, atk: 10, def: 18, mdef: 30, agi: 30, spr: 30),
                             [ { if: { round_multiple: 4 }, use: "echo_wall", target: "lowest_hp" }, { if: { round_multiple: 3 }, use: "quicken", target: "lowest_hp" },
                               { if: { chance: 25 }, use: "slow_tempo" }, { use: "sonar_lance" } ],
                             "Her voice: the song and the tempo. Magicians crew it, and it finds him under the water."),
      station_damage_control: station("Damage Control", stats(max_hp: 1000, max_mp: 100, mag: 40, str: 18, atk: 14, def: 36, mdef: 34, agi: 20, spr: 34),
                                      [ { if: { ally_ko: true }, use: "reboot" }, { if: { ally_hp_below: 50 }, use: "patch_hull", target: "lowest_hp" },
                                        { if: { round_multiple: 4 }, use: "seal_bulkheads" }, { use: "take_the_blow" } ],
                                      "Repair and reboot. Healers crew it, and Bodyguards, who turn her armour to meet him."),
      station_ordnance: station("Ordnance", stats(max_hp: 850, max_mp: 60, str: 40, atk: 52, def: 22, mdef: 18, agi: 30, spr: 14),
                                [ { once: true, if: { round_multiple: 5 }, use: "hail_bomb" }, { if: { chance: 30 }, use: "missile_salvo" }, { use: "drone_strike" } ],
                                "Missiles, drones and the hail bomb, with the reach for him wherever he is. Rangers crew it.")
    }.freeze

    # Deepest form first: each phase becomes an entry already in the Bestiary.
    FLEET_CRASHER = {
      fleet_crasher_enraged: { name: "Fleet Crasher (Enraged)", level: 15, boss: true, giant: true,
                               stats: stats(max_hp: 9999, str: 74, atk: 64, mag: 20, def: 20, mdef: 22, agi: 32, spr: 24),
                               base_type: "dragon", second_type: "fairy", exp: 2000, gil: 0, abp: 30, status_immune: %w[confuse rage sleep],
                               ai_script: [ { once: true, use: "frenzy", say: "No more sword-work." },
                                            { if: { round_multiple: 3 }, use: "crashing_lunge", target: "last_hit", say: "The bill goes back. He's picked a system." },
                                            { if: { chance: 40 }, use: "bill_storm" }, { use: "bill_slash" } ],
                               description: "He just wants her gone." },
      fleet_crasher_submerged: { name: "Fleet Crasher (Under)", level: 15, boss: true, giant: true,
                                 stats: stats(max_hp: 9999, str: 72, atk: 62, mag: 20, def: 22, mdef: 24, agi: 30, spr: 24),
                                 base_type: "dragon", second_type: "fairy", exp: 2000, gil: 0, abp: 30, status_immune: %w[confuse rage sleep],
                                 ai_script: [ { if: { round_multiple: 3 }, use: "sound_dive", target: "last_hit", say: "He goes under. The water goes very still." },
                                              { if: { chance: 35 }, use: "wave_crash" }, { use: "bill_slash" } ],
                                 phases: [ { hp_below: 33, becomes: "fleet_crasher_enraged", restore: 10, say: "He breaches, screaming, and the bill comes off his head for good." } ],
                                 description: "Under the water, and up beneath her systems." },
      fleet_crasher: { name: "Fleet Crasher", level: 15, boss: true, giant: true,
                       stats: stats(max_hp: 9999, str: 70, atk: 60, mag: 20, def: 26, mdef: 24, agi: 26, spr: 24),
                       base_type: "dragon", second_type: "fairy", exp: 2000, gil: 0, abp: 30, status_immune: %w[confuse rage sleep],
                       ai_script: [ { if: { round_multiple: 4 }, use: "crashing_lunge", target: "last_hit",
                                      say: "He draws the bill back, and fixes one eye on whatever hit him last." },
                                    { if: { round_multiple: 3 }, use: "buckler_up", say: "The chest plate comes up." },
                                    { if: { chance: 25 }, use: "tail_wave" }, { if: { chance: 30 }, use: "buckler_bash" }, { use: "bill_slash" } ],
                       phases: [ { hp_below: 66, becomes: "fleet_crasher_submerged", restore: 10, say: "He drops the plate, and goes under." } ],
                       boss_line: "The sea pulls back, and her brother comes up out of it: a dolphin the size of a district, a marlin bill strapped to his head.",
                       description: "Swirl-Pool's brother and rival, come to finish the old fight. Nonverbal, and known only by what he does." }
    }.freeze

    # Who crews what (Crew): each archetype at the station its fantasy fits,
    # and the cast's wearers, in the notes' order, at the stations theirs do.
    CREW = {
      stations: { courtsword: "station_blade", soldier: "station_blade", firemancer: "station_breath", watermancer: "station_breath",
                  thundermancer: "station_breath", earthmancer: "station_breath", windmancer: "station_breath", thief: "station_rigging",
                  monk: "station_drive", magician: "station_sonar", healer: "station_damage_control", bodyguard: "station_damage_control",
                  ranger: "station_ordnance" },
      default: "station_blade",
      wearers: [ { npc: "The Swordsman", station: "station_blade" }, { npc: "Amethyst 7A", station: "station_ordnance" },
                 { npc: "The King", station: "station_damage_control" } ],
      seats: 7, half_below: 4
    }.freeze
  end
end
