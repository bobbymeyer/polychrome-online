# frozen_string_literal: true

# The base world's first book entries (docs/HANDOFF.md §2: "The base world
# is seed data: the first World and its children").
#
# Idempotent: entries are matched by slug and updated in place, so this can
# be re-run after editing. Numbers are first-pass tuning (§9.2).
module Seeds
  module BaseWorld
    module_function

    def run
      world = World.find_or_initialize_by(slug: "base")
      world.update!(name: "Base World",
                    description: "The opinionated default setting: crystals, jobs, and a world map of towns, " \
                                 "dungeons and the roads between them.")

      ABILITIES.each { |slug, attrs| upsert(world.abilities, slug, attrs) }
      ITEMS.each { |slug, attrs| upsert(world.items, slug, attrs) }
      MONSTERS.each { |slug, attrs| upsert(world.monsters, slug, attrs) }
      JOBS.each do |slug, attrs|
        levels = attrs.fetch(:levels)
        job = upsert(world.jobs, slug, attrs.except(:levels))
        job.job_levels.destroy_all
        levels.each_with_index do |(ability, abp), i|
          job.job_levels.create!(level: i + 1, abp: abp, ability: world.abilities.find_by!(slug: ability))
        end
      end
      world
    end

    def upsert(scope, slug, attrs)
      record = scope.find_or_initialize_by(slug: slug.to_s)
      record.update!(attrs)
      record
    end

    def stats(max_hp:, max_mp: 0, str: 10, mag: 10, vit: 10, spr: 10, agi: 10, atk: 0, def: 0, mdef: 0)
      { max_hp:, max_mp:, str:, mag:, vit:, spr:, agi:, atk:, def:, mdef: }
    end

    ABILITIES = {
      fire: { name: "Fire", kind: "magic", target: "single_enemy", mp_cost: 4, gesture: "flash",
              effects: [ { primitive: "elemental", element: "fire", power: 20 } ],
              description: "A burst of flame. The first spell every black mage learns and the last one they forget." },
      blizzard: { name: "Blizzard", kind: "magic", target: "single_enemy", mp_cost: 4, gesture: "flash",
                  effects: [ { primitive: "elemental", element: "ice", power: 20 } ],
                  description: "Shards of ice that sting worse than they look." },
      thunder: { name: "Thunder", kind: "magic", target: "single_enemy", mp_cost: 4, gesture: "flash",
                 effects: [ { primitive: "elemental", element: "bolt", power: 20 } ],
                 description: "A single crack of lightning." },
      fira: { name: "Fira", kind: "magic", target: "all_enemies", mp_cost: 10, gesture: "flash",
              effects: [ { primitive: "elemental", element: "fire", power: 18 } ],
              description: "Fire spread across the whole enemy line." },
      sleep: { name: "Sleep", kind: "magic", target: "single_enemy", mp_cost: 3, gesture: "float",
               effects: [ { primitive: "status", kind: "sleep", chance: 70, duration: 3 } ],
               description: "Lulls a foe to sleep. A hard blow wakes them." },
      bio: { name: "Bio", kind: "magic", target: "single_enemy", mp_cost: 6, gesture: "tint",
             effects: [ { primitive: "elemental", element: "dark", power: 12 },
                       { primitive: "status", kind: "poison", chance: 100, duration: 4 } ],
             description: "Corrosive shadow that lingers as poison." },
      drain: { name: "Drain", kind: "magic", target: "single_enemy", mp_cost: 5, gesture: "tint",
               effects: [ { primitive: "drain", power: 20 } ],
               description: "Steals life from a foe and gives it to the caster." },
      cure: { name: "Cure", kind: "magic", target: "single_ally", mp_cost: 4, gesture: "float",
              effects: [ { primitive: "heal", power: 25 } ],
              description: "Closes wounds on a single ally." },
      cura: { name: "Cura", kind: "magic", target: "all_allies", mp_cost: 9, gesture: "float",
              effects: [ { primitive: "heal", power: 18 } ],
              description: "Gentler healing that reaches the whole party." },
      raise: { name: "Raise", kind: "magic", target: "single_ally", mp_cost: 10, gesture: "pop",
               effects: [ { primitive: "revive", fraction: 25 } ],
               description: "Calls a fallen ally back to their feet." },
      silence: { name: "Silence", kind: "magic", target: "single_enemy", mp_cost: 3, gesture: "fade",
                 effects: [ { primitive: "status", kind: "silence", chance: 80, duration: 3 } ],
                 description: "Steals a caster's voice." },
      haste: { name: "Haste", kind: "magic", target: "single_ally", mp_cost: 5, gesture: "spin",
               effects: [ { primitive: "status", kind: "haste", chance: 100, duration: 4 } ],
               description: "Quickens an ally's turns." },
      double_cut: { name: "Double Cut", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                    effects: [ { primitive: "physical", power: 60, hits: 2 } ],
                    description: "Two quick strikes in the time of one." },
      war_cry: { name: "War Cry", kind: "skill", target: "self", mp_cost: 2, gesture: "shake",
                 effects: [ { primitive: "buff", stat: "str", amount: 50, duration: 3 } ],
                 description: "A roar that steadies the arm." },
      armor_break: { name: "Armor Break", kind: "skill", target: "single_enemy", mp_cost: 2, gesture: "lunge",
                     effects: [ { primitive: "physical", power: 80 },
                               { primitive: "debuff", stat: "def", amount: 50, duration: 3 } ],
                     description: "A blow aimed at the seams of a foe's armor." },
      kick: { name: "Kick", kind: "skill", target: "all_enemies", mp_cost: 0, gesture: "spin",
              effects: [ { primitive: "physical", power: 50 } ],
              description: "A sweeping kick that catches every foe." },
      smoke_bomb: { name: "Smoke Bomb", kind: "skill", target: "self", mp_cost: 0, gesture: "fade",
                    effects: [ { primitive: "escape" } ],
                    description: "Guarantees an escape, if escape is possible at all." },
      goblin_punch: { name: "Goblin Punch", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                      effects: [ { primitive: "physical", power: 150 } ],
                      description: "An unreasonably strong punch from an unreasonably small creature." },
      venom_bite: { name: "Venom Bite", kind: "skill", target: "single_enemy", mp_cost: 0, gesture: "lunge",
                    effects: [ { primitive: "physical", power: 80 },
                              { primitive: "status", kind: "poison", chance: 60, duration: 3 } ],
                    description: "A bite that keeps hurting." },
      howl: { name: "Howl", kind: "skill", target: "all_allies", mp_cost: 0, gesture: "shake",
              effects: [ { primitive: "buff", stat: "agi", amount: 30, duration: 3 } ],
              description: "The pack moves faster together." }
    }.freeze

    ITEMS = {
      potion: { name: "Potion", category: "consumable", price: 40, target: "single_ally",
                effects: [ { primitive: "heal", power: 30 } ], description: "Restores a little HP." },
      phoenix_down: { name: "Phoenix Down", category: "consumable", price: 300, target: "single_ally",
                      effects: [ { primitive: "revive", fraction: 20 } ], description: "A feather that remembers being alive." },
      hi_potion: { name: "Hi-Potion", category: "consumable", price: 150, target: "single_ally",
                   effects: [ { primitive: "heal", power: 80 } ], description: "Restores a good deal of HP." },
      smoke_pellet: { name: "Smoke Pellet", category: "consumable", price: 80, target: "self",
                      effects: [ { primitive: "escape" } ], description: "For when the plan was bad." },
      broadsword: { name: "Broadsword", category: "sword", price: 200, stats: { atk: 14 },
                    description: "A plain, honest blade." },
      dagger: { name: "Dagger", category: "knife", price: 120, stats: { atk: 9, agi: 2 },
                description: "Light enough to strike first." },
      rod: { name: "Rod", category: "rod", price: 150, stats: { atk: 4, mag: 4 },
             description: "Wood, wire and a borrowed spark." },
      staff: { name: "Staff", category: "staff", price: 150, stats: { atk: 5, spr: 4 },
               description: "A walking stick that listens." },
      buckler: { name: "Buckler", category: "shield", price: 100, stats: { def: 3, mdef: 1 },
                 description: "Small, round, often dented." },
      leather_cap: { name: "Leather Cap", category: "hat", price: 60, stats: { def: 1, mdef: 1 },
                     description: "Keeps the rain off." },
      bronze_armor: { name: "Bronze Armor", category: "heavy_armor", price: 400, stats: { def: 8, agi: -2 },
                      description: "Heavy, loud and reassuring." },
      cotton_robe: { name: "Cotton Robe", category: "robe", price: 120, stats: { def: 2, mdef: 4 },
                     description: "Embroidered with small protective sigils." },
      power_ring: { name: "Power Ring", category: "accessory", price: 1000, stats: { str: 5 },
                    description: "A ring cut from a single garnet." }
    }.freeze

    JOBS = {
      freelancer: { name: "Freelancer", description: "No talents, no limits. Every hero starts here.",
                    stat_multipliers: {}, ability_slots: 2, equip_categories: Item::EQUIPMENT_CATEGORIES,
                    innates: [], levels: [] },
      knight: { name: "Knight", description: "Heavy armor, a long sword and the resolve to stand in front.",
                stat_multipliers: { max_hp: 130, str: 120, vit: 120, agi: 90, mag: 60 },
                equip_categories: %w[sword axe spear shield helmet heavy_armor accessory],
                innates: [ { stat: "def", percent: 10 } ],
                levels: [ [ "war_cry", 10 ], [ "armor_break", 20 ], [ "double_cut", 40 ] ] },
      thief: { name: "Thief", description: "Fast hands, faster feet.",
               stat_multipliers: { agi: 140, str: 90, max_hp: 90 },
               equip_categories: %w[knife hat light_armor accessory],
               innates: [ { stat: "agi", add: 5 } ],
               levels: [ [ "smoke_bomb", 10 ], [ "double_cut", 30 ] ] },
      monk: { name: "Monk", description: "Fists instead of steel.",
              stat_multipliers: { max_hp: 140, str: 130, vit: 110, mag: 50 },
              equip_categories: %w[light_armor accessory],
              innates: [ { stat: "atk", add: 12 } ],
              levels: [ [ "kick", 15 ], [ "war_cry", 25 ] ] },
      black_mage: { name: "Black Mage", description: "Destruction, studied carefully.",
                    stat_multipliers: { max_hp: 70, max_mp: 150, mag: 140, str: 60 },
                    equip_categories: %w[knife rod robe hat accessory],
                    innates: [],
                    levels: [ [ "fire", 10 ], [ "blizzard", 10 ], [ "thunder", 10 ], [ "sleep", 20 ], [ "fira", 40 ], [ "bio", 60 ], [ "drain", 80 ] ] },
      white_mage: { name: "White Mage", description: "Keeps everyone else alive.",
                    stat_multipliers: { max_hp: 80, max_mp: 140, mag: 120, spr: 130, str: 60 },
                    equip_categories: %w[staff robe hat accessory],
                    innates: [ { stat: "mdef", percent: 20 } ],
                    levels: [ [ "cure", 10 ], [ "silence", 20 ], [ "cura", 40 ], [ "haste", 50 ], [ "raise", 80 ] ] }
    }.freeze

    MONSTERS = {
      goblin: { name: "Goblin", level: 1, stats: stats(max_hp: 45, str: 9, atk: 8, agi: 8, def: 3, mdef: 2),
                elements: { fire: "weak" }, exp: 6, gil: 12, abp: 1,
                ai_script: [ { if: { chance: 25 }, use: "goblin_punch" }, { use: "attack" } ],
                drops: [ { item: "potion", chance: 30 } ],
                description: "Small, green and far braver in groups." },
      wolf: { name: "Wolf", level: 2, stats: stats(max_hp: 60, str: 11, atk: 10, agi: 16, def: 3, mdef: 3),
              exp: 9, gil: 8, abp: 1,
              ai_script: [ { if: { round_multiple: 3 }, use: "howl" }, { if: { chance: 30 }, use: "venom_bite" }, { use: "attack" } ],
              drops: [ { item: "potion", chance: 25 } ],
              description: "Hunts in packs along the old roads." },
      killer_bee: { name: "Killer Bee", level: 2, stats: stats(max_hp: 35, str: 8, atk: 9, agi: 22, def: 1, mdef: 2),
                    elements: { wind: "weak", earth: "immune" }, exp: 7, gil: 6, abp: 1,
                    ai_script: [ { if: { chance: 40 }, use: "venom_bite", target: "lowest_hp" }, { use: "attack" } ],
                    description: "The buzzing arrives before the bee does." },
      zombie: { name: "Zombie", level: 3, stats: stats(max_hp: 110, str: 12, atk: 12, agi: 4, def: 4, mdef: 1),
                elements: { fire: "weak", holy: "weak", dark: "absorb" }, status_immune: %w[poison sleep],
                exp: 14, gil: 20, abp: 1,
                ai_script: [ { use: "attack", target: "lowest_hp" } ],
                description: "Slow, relentless and already dead." },
      flan: { name: "Flan", level: 3,
              stats: stats(max_hp: 70, max_mp: 20, mag: 14, atk: 6, agi: 6, def: 60, mdef: 0),
              elements: { fire: "weak", ice: "resist", bolt: "resist" }, exp: 12, gil: 15, abp: 1,
              ai_script: [ { if: { chance: 50 }, use: "blizzard" }, { use: "attack" } ],
              description: "Blades bounce off. Bring a mage." },
      sand_worm: { name: "Sand Worm", level: 4, stats: stats(max_hp: 180, str: 15, atk: 14, agi: 6, def: 6, mdef: 4),
                   elements: { water: "weak", earth: "absorb" }, exp: 20, gil: 30, abp: 2,
                   ai_script: [ { if: { chance: 35 }, use: "venom_bite" }, { use: "attack", target: "highest_hp" } ],
                   drops: [ { item: "phoenix_down", chance: 10 } ],
                   description: "Rises from the dunes when something walks over it." },
      goblin_chief: { name: "Goblin Chief", level: 4,
                      stats: stats(max_hp: 140, max_mp: 12, str: 14, atk: 13, agi: 10, def: 5, mdef: 3, mag: 10),
                      elements: { fire: "weak" }, exp: 25, gil: 60, abp: 2,
                      ai_script: [ { if: { self_hp_below: 30 }, use: "cure", target: "self" },
                                  { if: { chance: 40 }, use: "goblin_punch" }, { use: "attack" } ],
                      drops: [ { item: "broadsword", chance: 15 } ],
                      variant: { hue: 40, scale: 125 },
                      description: "A goblin in a slightly bigger hat. Palette-swapped from the Goblin." },
      dark_mage: { name: "Dark Mage", level: 5,
                   stats: stats(max_hp: 120, max_mp: 60, str: 6, mag: 20, spr: 16, atk: 4, agi: 12, def: 3, mdef: 12),
                   elements: { holy: "weak", dark: "absorb" }, exp: 30, gil: 80, abp: 2,
                   ai_script: [ { if: { ally_hp_below: 40 }, use: "drain" }, { if: { chance: 30 }, use: "sleep" },
                               { if: { chance: 60 }, use: "fire" }, { use: "bio" } ],
                   drops: [ { item: "rod", chance: 20 } ],
                   description: "Studied at the same academy as the party's black mage. Graduated differently." },
      ogre: { name: "Ogre", level: 6,
              stats: stats(max_hp: 400, max_mp: 30, str: 20, mag: 8, atk: 18, agi: 7, def: 12, mdef: 6),
              elements: { ice: "absorb", fire: "resist" }, status_immune: %w[sleep], exp: 80, gil: 150, abp: 3,
              ai_script: [ { if: { self_hp_below: 30 }, use: "cure", target: "self" },
                          { if: { round_multiple: 3 }, use: "war_cry" }, { use: "attack", target: "lowest_hp" } ],
              drops: [ { item: "bronze_armor", chance: 50 }, { item: "power_ring", chance: 5 } ],
              description: "Guards the pass. A boss for a party of four at job level 2 or so." },
      crystal_wyrm: { name: "Crystal Wyrm", level: 10,
                      stats: stats(max_hp: 1200, max_mp: 200, str: 26, mag: 24, spr: 20, atk: 24, agi: 14, def: 16, mdef: 16),
                      elements: { bolt: "weak", fire: "resist", ice: "resist", earth: "immune" },
                      status_immune: %w[sleep paralyze silence poison], exp: 400, gil: 1000, abp: 8,
                      ai_script: [ { if: { self_hp_below: 25, chance: 50 }, use: "cura" },
                                  { if: { round_multiple: 4 }, use: "fira" }, { if: { chance: 30 }, use: "thunder" },
                                  { use: "attack" } ],
                      drops: [ { item: "power_ring", chance: 100 } ],
                      description: "Grew around a shard of the fire crystal. The first real boss." }
    }.freeze
  end
end
