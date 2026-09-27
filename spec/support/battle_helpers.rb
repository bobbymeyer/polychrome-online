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
                      effects: [ { primitive: "physical", power: 100, against: "sleep", bonus: 200 } ] }
    }
  end

  # Creatures abilities can call (the summon primitive).
  def summons
    {
      eagle: { name: "Eagle", stats: stats(max_hp: 40, str: 12, atk: 10, agi: 30), types: %w[flying], ai: [ { use: "talon" } ], abilities: %w[talon] },
      wisp: { name: "Wisp", stats: stats(max_hp: 30, mag: 14, agi: 20), types: %w[ghost], ai: [ { use: "chill" } ], abilities: %w[chill] }
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

  def build_battle(seed: 1, party: BattleFixtures.party, enemies: BattleFixtures.goblins,
                   abilities: BattleFixtures.abilities, escapable: true, items: {}, terrain: nil, types: nil, summons: BattleFixtures.summons)
    Battle::State.build(seed: seed, party: party, enemies: enemies, abilities: abilities, escapable: escapable, items: items, terrain: terrain,
                        types: types, summons: summons)
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
    awaiting = state["units"].select do |u|
      u["side"] == "party" && u["hp"].positive? && !u["guest"] && !u["gone"] &&
        u["statuses"].none? { |s| Battle::NO_INPUT_STATUSES.include?(s["kind"]) }
    end
    awaiting.reduce([ state, [] ]) do |(s, log), u|
      action = %w[defend flee].include?(ability) ? command(u["id"], kind: ability) : command(u["id"], ability)
      s, events = apply(s, action)
      [ s, log + events ]
    end
  end
end
