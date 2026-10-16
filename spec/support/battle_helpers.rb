# frozen_string_literal: true

# A tiny slice of the base world, as plain data, for resolver specs.
module BattleFixtures
  module_function

  def stats(**overrides)
    {
      max_hp: 100, max_mp: 20, str: 10, mag: 10, vit: 10, spr: 10,
      agi: 10, atk: 10, def: 5, mdef: 5
    }.merge(overrides).transform_keys(&:to_s)
  end

  def abilities
    {
      fire: { name: "Fire", kind: "magic", target: "single_enemy", cost: { mp: 4 },
              effects: [ { primitive: "elemental", type: "fire", power: 20, hits: 1 } ] },
      firaga_all: { name: "Fira", kind: "magic", target: "all_enemies", cost: { mp: 10 },
                    effects: [ { primitive: "elemental", type: "fire", power: 18 } ] },
      blizzard: { name: "Blizzard", kind: "magic", target: "single_enemy", cost: { mp: 4 },
                  effects: [ { primitive: "elemental", type: "ice", power: 20 } ] },
      cure: { name: "Cure", kind: "magic", target: "single_ally", cost: { mp: 4 },
              effects: [ { primitive: "heal", power: 25 } ] },
      cura: { name: "Cura", kind: "magic", target: "all_allies", cost: { mp: 9 },
              effects: [ { primitive: "heal", power: 18 } ] },
      raise: { name: "Raise", kind: "magic", target: "single_ally", cost: { mp: 10 },
               effects: [ { primitive: "revive", fraction: 25 } ] },
      bio: { name: "Bio", kind: "magic", target: "single_enemy", cost: { mp: 6 },
             effects: [ { primitive: "elemental", type: "dark", power: 12 },
                       { primitive: "status", kind: "poison", chance: 100, duration: 4 } ] },
      sleep: { name: "Sleep", kind: "magic", target: "single_enemy", cost: { mp: 3 },
               effects: [ { primitive: "status", kind: "sleep", chance: 70, duration: 3 } ] },
      silence: { name: "Silence", kind: "magic", target: "single_enemy", cost: { mp: 3 },
                 effects: [ { primitive: "status", kind: "silence", chance: 100, duration: 3 } ] },
      drain: { name: "Drain", kind: "magic", target: "single_enemy", cost: { mp: 5 },
               effects: [ { primitive: "drain", power: 20 } ] },
      double_cut: { name: "Double Cut", kind: "skill", target: "single_enemy", cost: { mp: 0 },
                    effects: [ { primitive: "physical", power: 60, hits: 2 } ] },
      war_cry: { name: "War Cry", kind: "skill", target: "self", cost: { mp: 2 },
                 effects: [ { primitive: "buff", stat: "str", amount: 50, duration: 3 } ] },
      armor_break: { name: "Armor Break", kind: "skill", target: "single_enemy", cost: { mp: 2 },
                     effects: [ { primitive: "debuff", stat: "def", amount: 50, duration: 3 } ] },
      haste: { name: "Haste", kind: "magic", target: "single_ally", cost: { mp: 5 },
               effects: [ { primitive: "status", kind: "haste", chance: 100, duration: 3 } ] },
      meteor: { name: "Meteor", kind: "magic", target: "random_enemy", cost: { mp: 15 },
                effects: [ { primitive: "elemental", type: "ground", power: 15, hits: 4 } ] },
      smoke_bomb: { name: "Smoke Bomb", kind: "skill", target: "self", cost: { mp: 0 },
                    effects: [ { primitive: "escape" } ] },
      goblin_punch: { name: "Goblin Punch", kind: "skill", target: "single_enemy", cost: { mp: 0 },
                      effects: [ { primitive: "physical", power: 150, hits: 1 } ] },
      esuna: { name: "Esuna", kind: "magic", target: "single_ally", cost: { mp: 5 },
               effects: [ { primitive: "cleanse" } ] },
      steal: { name: "Steal", kind: "skill", target: "single_enemy", cost: { mp: 0 },
               effects: [ { primitive: "steal", chance: 50 } ] },
      libra: { name: "Libra", kind: "magic", target: "single_enemy", cost: { mp: 1 },
               effects: [ { primitive: "scan" } ] },
      cover: { name: "Cover", kind: "skill", target: "self", cost: { mp: 0 },
               effects: [ { primitive: "status", kind: "cover", chance: 100, duration: 2 } ] },
      jump: { name: "Jump", kind: "skill", target: "single_enemy", cost: { mp: 0 },
              effects: [ { primitive: "jump", power: 200 } ] },
      gaia: { name: "Gaia", kind: "skill", target: "all_enemies", cost: { mp: 0 },
              effects: [ { primitive: "elemental", type: "terrain", power: 12 } ] },
      hide: { name: "Hide", kind: "skill", target: "self", cost: { mp: 0 },
              effects: [ { primitive: "away", who: "self", duration: 1 } ] },
      banish: { name: "Banish", kind: "magic", target: "single_enemy", cost: { mp: 2 },
                effects: [ { primitive: "away", who: "target", duration: 2, chance: 80 } ] },
      high_jump: { name: "High Jump", kind: "skill", target: "single_enemy", cost: { mp: 0 },
                   effects: [ { primitive: "away", who: "self", duration: 2, power: 250 } ] },
      barrier: { name: "Barrier", kind: "magic", target: "single_ally", cost: { mp: 4 }, effects: [ { primitive: "shield", power: 6 } ] },
      taunt: { name: "Taunt", kind: "skill", target: "self", cost: { mp: 0 }, effects: [ { primitive: "status", kind: "aggro", duration: 2 } ] },
      stop: { name: "Stop", kind: "magic", target: "single_enemy", cost: { mp: 5 }, effects: [ { primitive: "status", kind: "stop", chance: 60, duration: 2 } ] },
      rage: { name: "Rage", kind: "skill", target: "single_enemy", cost: { mp: 2 }, effects: [ { primitive: "status", kind: "berserk", chance: 70, duration: 2 } ] },
      confuse: { name: "Confuse", kind: "magic", target: "single_enemy", cost: { mp: 3 }, effects: [ { primitive: "status", kind: "confuse", chance: 70, duration: 3 } ] },
      focus: { name: "Focus", kind: "skill", target: "self", cost: { mp: 0 }, effects: [ { primitive: "status", kind: "charged", duration: 3 } ] },
      flame_blade: { name: "Flame Blade", kind: "magic", target: "self", cost: { mp: 3 }, effects: [ { primitive: "imbue", type: "fire", duration: 3 } ] },
      gravity: { name: "Gravity", kind: "magic", target: "single_enemy", cost: { mp: 6 }, effects: [ { primitive: "percent", power: 25, chance: 80 } ] },
      osmose: { name: "Osmose", kind: "magic", target: "single_enemy", cost: { mp: 0 }, effects: [ { primitive: "sap", power: 20, keep: 100 } ] },
      blood_strike: { name: "Blood Strike", kind: "skill", target: "single_enemy", cost: { mp: 0, hp: 10 }, effects: [ { primitive: "physical", power: 180 } ] },
      holy: { name: "Holy", kind: "magic", target: "single_enemy", cost: { mp: 6 },
              effects: [ { primitive: "elemental", type: "psychic", power: 18, against: "undead", bonus: 300 } ] },
      comet: { name: "Comet", kind: "magic", target: "all_enemies", cost: { mp: 8 }, charge: 1,
               effects: [ { primitive: "elemental", type: "rock", power: 30 } ] },
      doom: { name: "Doom", kind: "magic", target: "single_enemy", cost: { mp: 8 }, effects: [ { primitive: "status", kind: "doom", chance: 50, duration: 2 } ] },
      reckless: { name: "Reckless Strike", kind: "skill", target: "single_enemy", cost: { mp: 0 }, effects: [ { primitive: "physical", power: 200, recoil: 25 } ] },
      revenge: { name: "Revenge", kind: "skill", target: "single_enemy", cost: { mp: 0 }, effects: [ { primitive: "physical", power: 100, grudge: 200 } ] },
      call_eagle: { name: "Call Eagle", kind: "magic", target: "self", cost: { mp: 4 }, effects: [ { primitive: "summon", creature: "eagle" } ] },
      call_wisp: { name: "Call Wisp", kind: "magic", target: "self", cost: { mp: 6 }, effects: [ { primitive: "summon", creature: "wisp", duration: 2, power: 150 } ] },
      talon: { name: "Talon Dive", kind: "skill", target: "single_enemy", cost: { mp: 0 }, effects: [ { primitive: "physical", type: "flying", power: 160 } ] },
      chill: { name: "Chill", kind: "magic", target: "all_enemies", cost: { mp: 0 }, effects: [ { primitive: "elemental", type: "ghost", power: 10 } ] },
      sneak_attack: { name: "Sneak Attack", kind: "skill", target: "single_enemy", cost: { mp: 0 },
                      effects: [ { primitive: "physical", power: 100, against: "sleep", bonus: 200 } ] },
      # Oda's archetypes (docs/ODA.md).
      sheathe: { name: "Sheathe", kind: "skill", target: "self", cost: { mp: 0 },
                 effects: [ { primitive: "gather", kind: "sheathed" }, { primitive: "buff", stat: "def", amount: 30, duration: 1 } ] },
      draw: { name: "Draw", kind: "skill", target: "all_enemies", cost: { mp: 0 },
              effects: [ { primitive: "physical", power: 60, with: "sheathed", boost: 60, patience: 15 } ] },
      zantetsu: { name: "Zantetsu", kind: "skill", target: "single_enemy", cost: { mp: 4 },
                  effects: [ { primitive: "physical", power: 80, against: "wounded", bonus: 300 } ] },
      iai_stance: { name: "Iai Stance", kind: "skill", target: "self", cost: { mp: 0 }, effects: [ { primitive: "status", kind: "iai", duration: 2 } ] },
      palm: { name: "Palm Strike", kind: "skill", target: "single_enemy", cost: { mp: 0 },
              effects: [ { primitive: "physical", power: 90 }, { primitive: "gather", kind: "chi" } ] },
      dragon_fist: { name: "Dragon Fist", kind: "skill", target: "single_enemy", cost: { mp: 0 },
                     effects: [ { primitive: "physical", power: 100, pierce: 50, with: "chi", boost: 40 } ] },
      firaja: { name: "Firaja", kind: "magic", target: "single_enemy", cost: { mp: 12 }, reload: 1,
                effects: [ { primitive: "elemental", type: "fire", power: 40, unresisted: 1 } ] },
      scorch: { name: "Scorch", kind: "magic", target: "single_enemy", cost: { mp: 3 }, effects: [ { primitive: "status", kind: "burn", chance: 80, duration: 3 } ] },
      dispel: { name: "Dispel", kind: "magic", target: "single_enemy", cost: { mp: 3 }, effects: [ { primitive: "dispel" } ] },
      reflect: { name: "Reflect", kind: "magic", target: "single_ally", cost: { mp: 4 }, effects: [ { primitive: "status", kind: "reflect", duration: 3 } ] },
      quick: { name: "Quick", kind: "magic", target: "single_ally", cost: { mp: 6 }, effects: [ { primitive: "quick" } ] },
      mimic: { name: "Mimic", kind: "skill", target: "self", cost: { mp: 0 }, effects: [ { primitive: "mimic" } ] },
      regen: { name: "Regen", kind: "magic", target: "single_ally", cost: { mp: 4 }, effects: [ { primitive: "status", kind: "regen", duration: 4 } ] },
      reraise: { name: "Reraise", kind: "magic", target: "single_ally", cost: { mp: 8 }, effects: [ { primitive: "status", kind: "reraise", duration: 5 } ] },
      triage: { name: "Triage", kind: "magic", target: "single_ally", cost: { mp: 3 }, effects: [ { primitive: "heal", power: 15, triage: 200 } ] },
      pilfer_boon: { name: "Lift", kind: "skill", target: "single_enemy", cost: { mp: 0 }, effects: [ { primitive: "steal", chance: 60, boon: 1 } ] },
      long_shot: { name: "Long Shot", kind: "skill", target: "single_enemy", cost: { mp: 0 }, reach: true, reload: 1,
                   effects: [ { primitive: "physical", power: 170, type: "flying" } ] },
      volley: { name: "Volley", kind: "skill", target: "random_enemy", cost: { mp: 2 }, reach: true,
                effects: [ { primitive: "physical", power: 50, hits: 3 } ] },
      call_hawk: { name: "Call Hawk", kind: "skill", target: "self", cost: { mp: 3 }, effects: [ { primitive: "summon", creature: "hawk", stays: 1 } ] },
      don_mask: { name: "Don the Storm Mask", kind: "skill", target: "self", cost: { mp: 0 }, effects: [ { primitive: "transform", mask: "storm_mask" } ] },
      raijin: { name: "Raijin", kind: "skill", target: "all_enemies", cost: { mp: 0 }, effects: [ { primitive: "physical", type: "electric", power: 120 } ] },
      # The Just Seven's guardians' moves (docs/ODA.md §9), for the menagerie below.
      clamp: { name: "Clamp", kind: "skill", target: "single_enemy", effects: [ { primitive: "grab", duration: 3, breaks: "fire" } ] },
      coil: { name: "Coil", kind: "skill", target: "single_enemy", effects: [ { primitive: "grab", duration: 2, tear: 10 } ] },
      pilfer: { name: "Pilfer", kind: "skill", target: "single_enemy", effects: [ { primitive: "steal", chance: 70 } ] },
      riposte: { name: "Riposte", kind: "skill", target: "single_enemy", effects: [ { primitive: "physical", power: 60 } ] },
      snap: { name: "Snap", kind: "skill", target: "single_enemy", effects: [ { primitive: "physical", power: 50 } ] },
      bill: { name: "Hooked Bill", kind: "skill", target: "single_enemy", effects: [ { primitive: "physical", power: 50 } ] },
      dive: { name: "Dive", kind: "skill", target: "single_enemy", charge: 1, effects: [ { primitive: "physical", power: 80, stumble: 1 } ] },
      circle: { name: "Circle", kind: "skill", target: "self", effects: [ { primitive: "away", who: "self", duration: 1, aloft: 1 } ] },
      flash: { name: "Belly Flash", kind: "skill", target: "all_enemies", charge: 1, interrupt: 2,
               effects: [ { primitive: "elemental", type: "fire", power: 25 } ] },
      tide: { name: "Tide Call", kind: "skill", target: "all_enemies", again: true, effects: [ { primitive: "elemental", type: "water", power: 8 } ] },
      lash: { name: "Tongue Lash", kind: "skill", target: "single_enemy", effects: [ { primitive: "physical", power: 50 } ] }
    }
  end

  # The monsters The Just Seven brought to the engine, in groups a random
  # table can meet (RandomTable): a boss with forms (the second smaller than
  # the first) and minions that answer blows, mourn and take a last breath;
  # a grabber and a thief; a striker that answers up close and a bird that
  # dives at whoever hit it last; a toad that winds up and goes again.
  def menagerie
    [ [ warden, *imps ], [ crab, raccoon ], [ mantis, cormorant ], [ toad, *imps(1) ] ]
  end

  def warden
    unbound = { name: "Warden Unbound", stats: stats(max_hp: 160, max_mp: 0, str: 16, atk: 14, agi: 9, def: 6, mdef: 4), types: %w[fire],
                abilities: %w[goblin_punch], ai: [ { use: "goblin_punch" } ], rewards: { exp: 40, gil: 60 } }
    # Smaller than the HP it comes in with, and nothing given back: the phase itself cuts the HP. It dives away as it falls.
    last = unbound.merge(name: "Warden, Last Breath", stats: stats(max_hp: 40, max_mp: 0, str: 20, atk: 18, agi: 11, def: 2, mdef: 2),
                         abilities: %w[goblin_punch hide], ai: [ { use: "goblin_punch" }, { when: "falls", use: "hide" } ])
    { id: "warden", name: "Warden", boss: true, stats: stats(max_hp: 380, max_mp: 0, str: 12, atk: 11, agi: 7, def: 6, mdef: 4),
      types: %w[normal], rewards: { exp: 30, gil: 40 }, abilities: %w[snap hide],
      phases: [ { hp_below: 70, becomes: unbound, say: "Enough.", restore: 10 }, { hp_below: 35, becomes: last } ],
      ai: [ { use: "attack" }, { when: "hit", use: "snap" }, { when: "falls", use: "hide" } ] }
  end

  def imps(count = 2)
    [ { id: "imp", name: "Imp", count: count, stats: stats(max_hp: 40, max_mp: 10, str: 8, atk: 7, agi: 12, def: 2, mdef: 2), types: %w[dark],
        rewards: { exp: 5, gil: 6 }, abilities: %w[snap goblin_punch call_eagle],
        ai: [ { when: "hit", use: "snap" }, { when: "ally_falls", once: true, say: "Cousin!", use: "goblin_punch" },
              { when: "falls", use: "call_eagle" }, { use: "attack" } ] } ]
  end

  def crab
    { id: "crab", name: "Crab", stats: stats(max_hp: 160, max_mp: 0, str: 12, atk: 11, agi: 5, def: 10, mdef: 6), types: %w[water],
      rewards: { exp: 20, gil: 20 }, abilities: %w[clamp coil],
      ai: [ { when: "falls", use: "clamp" }, { if: { chance: 50 }, use: "clamp", target: "lowest_hp" }, { use: "coil" } ] }
  end

  def raccoon
    { id: "raccoon", name: "Raccoon", stats: stats(max_hp: 70, max_mp: 0, str: 8, atk: 8, agi: 30, def: 3, mdef: 3), types: %w[dark],
      rewards: { exp: 10, gil: 15 }, abilities: %w[pilfer], ai: [ { if: { chance: 60 }, use: "pilfer" }, { use: "attack" } ] }
  end

  def mantis
    { id: "mantis", name: "Mantis", stats: stats(max_hp: 140, max_mp: 0, str: 14, atk: 13, agi: 14, def: 5, mdef: 3), types: %w[bug],
      rewards: { exp: 18, gil: 20 }, abilities: %w[riposte], ai: [ { when: "struck", use: "riposte" }, { use: "attack" } ] }
  end

  def cormorant
    { id: "cormorant", name: "Cormorant", stats: stats(max_hp: 110, max_mp: 0, str: 11, atk: 10, agi: 16, def: 4, mdef: 3), types: %w[flying],
      rewards: { exp: 16, gil: 18 }, abilities: %w[bill dive circle],
      ai: [ { if: { chance: 20 }, use: "circle" }, { if: { chance: 30 }, use: "dive", target: "last_hit" }, { use: "bill", target: "last_hit" } ] }
  end

  def toad
    { id: "toad", name: "Toad", stats: stats(max_hp: 260, max_mp: 0, str: 12, atk: 11, mag: 12, agi: 6, def: 5, mdef: 5), types: %w[water],
      rewards: { exp: 30, gil: 30 }, abilities: %w[flash tide lash],
      ai: [ { use: "tide", once: true }, { if: { chance: 40 }, use: "flash" }, { use: "lash" } ] }
  end

  # Water that rises as the fight goes on (Battle::Conditions), to its chest-deep last.
  def rising_water
    { stages: [ { name: "Ankle-deep", rounds: 2, conditions: [ { kind: "weaken", type: "fire", amount: 50 } ] },
                { name: "Waist-deep", rounds: 2, conditions: [ { kind: "slow", amount: 25 }, { kind: "dark", amount: 10 } ] },
                { name: "Chest-deep", conditions: [ { kind: "conduct", type: "electric" }, { kind: "drown", amount: 8, spares: "water" } ] } ] }
  end

  # What the transform primitive puts on.
  def masks
    { storm_mask: { name: "Storm Mask", type: "electric", duration: 3, abilities: %w[raijin] } }
  end

  # Creatures abilities can call (the summon primitive).
  def summons
    {
      eagle: { name: "Eagle", stats: stats(max_hp: 40, str: 12, atk: 10, agi: 30), types: %w[flying], ai: [ { use: "talon" } ], abilities: %w[talon] },
      wisp: { name: "Wisp", stats: stats(max_hp: 30, mag: 14, agi: 20), types: %w[ghost], ai: [ { use: "chill" } ], abilities: %w[chill] },
      hawk: { name: "Hawk", stats: stats(max_hp: 35, str: 10, atk: 8, agi: 28), types: %w[flying], ai: [ { use: "talon" } ], abilities: %w[talon] }
    }
  end

  # The party's shared items (§3.1: same effect vocabulary as abilities).
  def items(potion: 2, phoenix_down: 1, antidote: 1, remedy: 1)
    {
      potion: { name: "Potion", target: "single_ally", effects: [ { primitive: "heal", power: 30 } ], count: potion },
      phoenix_down: { name: "Phoenix Down", target: "single_ally", effects: [ { primitive: "revive", fraction: 25 } ], count: phoenix_down },
      antidote: { name: "Antidote", target: "single_ally", effects: [ { primitive: "cleanse", kind: "poison" } ], count: antidote },
      remedy: { name: "Remedy", target: "single_ally", effects: [ { primitive: "cleanse" } ], count: remedy }
    }
  end

  def party
    [
      { id: "bartz", name: "Bartz", stats: stats(max_hp: 120, str: 14, atk: 14, agi: 12, def: 8),
        abilities: %w[double_cut war_cry armor_break smoke_bomb] },
      { id: "vivi", name: "Vivi", stats: stats(max_hp: 70, max_mp: 40, mag: 18, str: 6, atk: 4, agi: 9),
        abilities: %w[fire firaga_all blizzard bio sleep silence drain meteor] },
      { id: "rosa", name: "Rosa", stats: stats(max_hp: 80, max_mp: 40, mag: 16, spr: 16, atk: 5, agi: 10),
        abilities: %w[cure cura raise haste libra] },
      { id: "locke", name: "Locke", stats: stats(max_hp: 90, str: 11, atk: 12, agi: 18),
        abilities: %w[double_cut smoke_bomb steal] }
    ]
  end

  def goblins(count = 3)
    [ { id: "goblin", name: "Goblin", count: count,
       stats: stats(max_hp: 45, max_mp: 0, str: 9, atk: 8, agi: 8, def: 3, mdef: 2),
       types: %w[normal], affinities: { fire: "weak" }, rewards: { exp: 6, gil: 12 }, drops: [ { item: "potion", chance: 30 } ],
       abilities: %w[goblin_punch],
       ai: [ { if: { chance: 25 }, use: "goblin_punch" }, { use: "attack" } ] } ]
  end

  # Bones that remember how to hold a sword: healing hurts them.
  def skeletons(count = 2)
    [ { id: "skeleton", name: "Skeleton", count: count, undead: true, stats: stats(max_hp: 60, max_mp: 10, str: 10, atk: 9, agi: 7, def: 4, mdef: 2),
        types: %w[ghost], rewards: { exp: 8, gil: 10 }, abilities: %w[confuse], ai: [ { if: { chance: 20 }, use: "confuse" }, { use: "attack" } ] } ]
  end

  # A thing woken from the deep: masks are made for it. It reflects, and
  # sometimes cuts first.
  def giant
    [ { id: "oni", name: "Oni", giant: true, boss: true,
        stats: stats(max_hp: 350, max_mp: 30, str: 18, atk: 16, agi: 6, def: 10, mdef: 8, mag: 10),
        types: %w[rock], rewards: { exp: 90, gil: 120 }, abilities: %w[reflect iai_stance fire],
        ai: [ { if: { round_multiple: 4 }, use: "reflect", target: "self" }, { if: { chance: 20 }, use: "iai_stance" },
              { if: { chance: 20 }, use: "fire" }, { use: "attack" } ] } ]
  end

  def ogre
    [ { id: "ogre", name: "Ogre", boss: true,
       stats: stats(max_hp: 400, max_mp: 30, str: 20, atk: 18, agi: 7, def: 12, mdef: 6, mag: 8),
       types: %w[normal], affinities: { ice: "absorb", fire: "resist" }, status_immune: %w[sleep], rewards: { exp: 80, gil: 150 },
       abilities: %w[cure war_cry],
       ai: [ { if: { self_hp_below: 30 }, use: "cure", target: "self" },
            { if: { round_multiple: 3 }, use: "war_cry" },
            { use: "attack", target: "lowest_hp" } ] } ]
  end
end

module BattleHelpers
  def stats(**overrides) = BattleFixtures.stats(**overrides)

  # A night's rest where the party is: rooms at the inn in a town with one
  # (camp is for the road), paid for by the GM.
  def rest_the_night(campaign)
    return campaign.sleep! unless campaign.inn_here

    campaign.update!(gil: campaign.gil + 10_000)
    campaign.spend_time!(campaign.current_node, "Rooms at #{campaign.inn_here['name']}")
  end

  def build_battle(seed: 1, party: BattleFixtures.party, enemies: BattleFixtures.goblins,
                   abilities: BattleFixtures.abilities, escapable: true, items: {}, terrain: nil, types: nil, summons: BattleFixtures.summons, rules: {},
                   masks: nil, field: nil, waves: [])
    # The fixtures' Storm Mask is electric: a world without it has no mask.
    masks ||= types ? {} : BattleFixtures.masks
    Battle::State.build(seed: seed, party: party, enemies: enemies, abilities: abilities, escapable: escapable, items: items, terrain: terrain,
                        types: types, summons: summons, rules: rules, masks: masks, field: field, waves: waves)
  end

  def apply(state, action)
    Battle::Resolver.apply(state, action)
  end

  def command(actor, ability = "attack", target = nil, kind: "ability")
    { type: "command", actor: actor, command: { kind: kind, ability: ability, target: target } }
  end

  def gm(op, **params)
    { type: "gm_override", actor: "gm", op: op, **params }
  end

  def unit(state, id)
    state["units"].find { |u| u["id"] == id }
  end

  def of_type(events, type)
    events.select { |e| e["type"] == type.to_s }
  end

  def types(events)
    events.map { |e| e["type"] }
  end

  # Replace a unit's fields in a state (test setup only).
  def with_unit(state, id, **fields)
    state = Battle::State.normalize(state)
    unit(state, id).merge!(fields.transform_keys(&:to_s))
    Battle::State.normalize(state)
  end

  # Events of one unit's turn, from turn_start to (excluding) turn_end.
  def turn_of(events, id)
    events.drop_while { |e| e["type"] != "turn_start" || e["unit"] != id }
          .take_while { |e| e["type"] != "turn_end" }
  end

  # Submit the same kind of command for every party member awaiting input.
  def full_round(state, ability = "attack")
    Battle::State.able_to_act(state).reduce([ state, [] ]) do |(s, log), id|
      action = %w[defend flee].include?(ability) ? command(id, kind: ability) : command(id, ability)
      s, events = apply(s, action)
      [ s, log + events ]
    end
  end
end
