# frozen_string_literal: true

module Stats
  # Every stat a unit carries. Derived values live in battle state under
  # unit["stats"]; current hp/mp live beside them.
  NAMES = %w[max_hp max_mp str mag vit spr agi atk def mdef].freeze

  # Stats that buffs, debuffs and stat-altering statuses may touch.
  # Pools (max_hp/max_mp) are deliberately excluded.
  MODIFIABLE = %w[str mag vit spr agi atk def mdef].freeze

  CAPS = {
    "max_hp" => 9999, "max_mp" => 999,
    "str" => 255, "mag" => 255, "vit" => 255, "spr" => 255, "agi" => 255,
    "atk" => 999, "def" => 999, "mdef" => 999
  }.freeze

  # Statuses that change stats, as percent modifiers. They stack additively
  # with buffs before the combined modifier is clamped.
  STATUS_MODIFIERS = {
    "haste" => { "agi" => 50 },
    "slow" => { "agi" => -50 },
    "berserk" => { "str" => 50 },
    # Wearing a mask (Battle::Masks), and worn out after one.
    "masked" => { "str" => 50, "mag" => 50, "agi" => 25, "def" => 30, "mdef" => 30 },
    "spent" => { "str" => -30, "mag" => -30, "agi" => -50 }
  }.freeze

  MODIFIER_FLOOR = -90
  MODIFIER_CEILING = 200

  # Pure stat derivation. All arithmetic is integer; percentages are whole
  # numbers (120 means x1.2). Keys are strings so results round-trip JSON.
  #
  #   derived   = clamp(((base * job% ) + equipment + passive adds) * (100 + passive%)%)
  #   effective = clamp(derived * (100 + buffs% + statuses%)%)
  module Derivation
    module_function

    # base:      { "str" => 12, ... } — character level/base stats
    # job:       { "multipliers" => { "str" => 120 } } — percent per stat, default 100
    # equipment: [{ "stats" => { "atk" => 10 } }, ...] — flat additions
    # passives:  [{ "stat" => "agi", "add" => 5 } | { "stat" => "str", "percent" => 10 }, ...]
    def derive(base:, job: {}, equipment: [], passives: [])
      base = stringify(base)
      multipliers = stringify(stringify(job || {}).fetch("multipliers", {}))
      unknown = (base.keys + multipliers.keys) - NAMES
      raise ArgumentError, "unknown stats: #{unknown.join(', ')}" if unknown.any?

      NAMES.to_h do |name|
        value = Integer(base.fetch(name, 0)) * Integer(multipliers.fetch(name, 100)) / 100
        value += equipment.sum { |piece| Integer(stringify(stringify(piece).fetch("stats", {})).fetch(name, 0)) }

        name_passives = passives.map { |p| stringify(p) }.select { |p| p["stat"].to_s == name }
        value += name_passives.sum { |p| Integer(p.fetch("add", 0)) }
        percent = name_passives.sum { |p| Integer(p.fetch("percent", 0)) }
        value = value * (100 + percent) / 100

        [ name, clamp(name, value) ]
      end
    end

    # stats:    derived stats hash
    # buffs:    [{ "stat" => "str", "amount" => 50, "turns" => 3 }] — amount is percent, negative for debuffs
    # statuses: ["haste", ...] — status kinds currently on the unit
    def effective(stats, buffs: [], statuses: [])
      stats = stringify(stats)
      modifiers = Hash.new(0)
      buffs.each do |buff|
        buff = stringify(buff)
        modifiers[buff["stat"]] += Integer(buff["amount"])
      end
      statuses.each do |kind|
        STATUS_MODIFIERS.fetch(kind.to_s, {}).each { |stat, pct| modifiers[stat] += pct }
      end

      stats.to_h do |name, value|
        pct = modifiers[name].clamp(MODIFIER_FLOOR, MODIFIER_CEILING)
        pct = 0 unless MODIFIABLE.include?(name)
        [ name, clamp(name, Integer(value) * (100 + pct) / 100) ]
      end
    end

    def clamp(name, value)
      floor = name == "max_hp" ? 1 : 0
      value.clamp(floor, CAPS.fetch(name))
    end

    def stringify(hash)
      hash.to_h { |k, v| [ k.to_s, v ] }
    end
  end
end
