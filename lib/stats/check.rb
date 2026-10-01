# frozen_string_literal: true

module Stats
  # A check the GM calls outside battle: can this character climb the wall,
  # talk the guard round, read the old script? Pure: the roll comes from the
  # RNG passed in (the campaign's, so it replays), and the modifiers from the
  # character's stat against what's typical for their level, and any bonus
  # (an archetype good at the check's skill, an origin).
  #
  # High is good, as everywhere: a d100, then each modifier in turn, and the
  # total has to reach what the difficulty needs (51 at normal: a character
  # with the stat typical for their level has an even chance). Each point of
  # stat above or below typical moves the roll, by less at higher levels,
  # where stats are bigger. The die has the last word either way: a natural
  # 1–5 always fails and a natural 96–100 always succeeds, so nothing is
  # ever certain.
  module Check
    STATS = %w[str mag vit spr agi].freeze
    # The total a roll must reach.
    DIFFICULTIES = { "easy" => 36, "normal" => 51, "hard" => 66, "heroic" => 81 }.freeze
    SWING = 60 # points of roll across one typical stat's worth of difference
    MAX_BONUS = 50
    ALWAYS_FAILS = 5
    ALWAYS_SUCCEEDS = 96

    module_function

    # What the stat adds to (or takes from) the roll.
    def stat_modifier(stat_value:, stat:, level:)
      raise ArgumentError, "unknown stat #{stat}" unless STATS.include?(stat)

      typical = Growth.base_stats(level).fetch(stat)
      (stat_value - typical) * SWING / typical
    end

    def needed(difficulty)
      DIFFICULTIES.fetch(difficulty) { raise ArgumentError, "unknown difficulty #{difficulty}" }
    end

    # The odds, in percent (5–95), for forms and forecasts.
    def chance(stat_value:, stat:, level:, difficulty:, bonus: 0)
      raise ArgumentError, "bonus must be 0 to #{MAX_BONUS}" unless bonus.is_a?(Integer) && bonus.between?(0, MAX_BONUS)

      modifier = stat_modifier(stat_value: stat_value, stat: stat, level: level) + bonus
      (101 - (needed(difficulty) - modifier)).clamp(ALWAYS_FAILS, ALWAYS_SUCCEEDS - 1)
    end

    # rng: anything with #int(n). bonuses: [{ "label", "amount" }], each a
    # modifier of its own after the stat's. Returns { "chance", "roll",
    # "modifiers" => [{ "label", "amount" }], "total", "needed", "success" }.
    def roll(stat_value:, stat:, level:, difficulty:, rng:, bonuses: [], bonus: nil)
      bonuses = [ { "label" => "Bonus", "amount" => bonus } ] if bonus && bonuses.empty?
      total_bonus = bonuses.sum { |b| b["amount"].to_i }
      odds = chance(stat_value: stat_value, stat: stat, level: level, difficulty: difficulty, bonus: total_bonus)
      # Each step that moves the roll (a modifier of nothing isn't one).
      modifiers = ([ { "label" => stat, "amount" => stat_modifier(stat_value: stat_value, stat: stat, level: level) } ] +
                   bonuses.map { |b| { "label" => b["label"].to_s, "amount" => b["amount"].to_i } }).reject { |m| m["amount"].zero? }
      roll = rng.int(100) + 1
      total = roll + modifiers.sum { |m| m["amount"] }
      needed = needed(difficulty)
      success = roll >= ALWAYS_SUCCEEDS || (roll > ALWAYS_FAILS && total >= needed)
      { "chance" => odds, "roll" => roll, "modifiers" => modifiers, "total" => total, "needed" => needed, "success" => success }
    end
  end
end
