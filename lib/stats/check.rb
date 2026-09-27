# frozen_string_literal: true

module Stats
  # A check the GM calls outside battle: can this character climb the wall,
  # talk the guard round, read the old script? Pure: the chance comes from
  # the character's stat against what's typical for their level, and the
  # roll from the RNG passed in (the campaign's, so it replays).
  #
  # At "normal", a character with the stat typical for their level has an
  # even chance. Each point above or below moves it, by less at higher
  # levels, where stats are bigger. Nothing is ever certain: 5% to 95%.
  module Check
    STATS = %w[str mag vit spr agi].freeze
    DIFFICULTIES = { "easy" => 75, "normal" => 100, "hard" => 125, "heroic" => 150 }.freeze
    SWING = 60 # percentage points across one typical stat's worth of difference

    module_function

    def chance(stat_value:, stat:, level:, difficulty:)
      raise ArgumentError, "unknown stat #{stat}" unless STATS.include?(stat)

      percent = DIFFICULTIES.fetch(difficulty) { raise ArgumentError, "unknown difficulty #{difficulty}" }
      typical = Growth.base_stats(level).fetch(stat)
      target = typical * percent / 100
      (50 + ((stat_value - target) * SWING / typical)).clamp(5, 95)
    end

    # rng: anything with #int(n). Returns { "chance", "roll", "success" }:
    # a roll of 1–100, a success at or under the chance.
    def roll(stat_value:, stat:, level:, difficulty:, rng:)
      odds = chance(stat_value: stat_value, stat: stat, level: level, difficulty: difficulty)
      roll = rng.int(100) + 1
      { "chance" => odds, "roll" => roll, "success" => roll <= odds }
    end
  end
end
