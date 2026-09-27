# frozen_string_literal: true

module Battle
  # Damage types and how they meet: Pokémon's type chart, less fairy and
  # dragon. A move's type against the target's type(s) makes it super
  # effective (x2), not very effective (x1/2) or of no effect at all; two
  # types multiply. A move with no type (the basic Attack) is always neutral.
  #
  # A unit's own affinities (a boss immune to fire, a slime that drinks
  # water) are exceptions on top of the chart: weak doubles, resist halves,
  # immune stops it, absorb heals instead.
  module Types
    ALL = %w[normal fire water electric grass ice fighting poison ground flying psychic bug rock ghost dark steel].freeze

    # attacking type => { defending type => percent }; unlisted is 100.
    CHART = {
      "normal" => { "rock" => 50, "ghost" => 0, "steel" => 50 },
      "fire" => { "fire" => 50, "water" => 50, "grass" => 200, "ice" => 200, "bug" => 200, "rock" => 50, "steel" => 200 },
      "water" => { "fire" => 200, "water" => 50, "grass" => 50, "ground" => 200, "rock" => 200 },
      "electric" => { "water" => 200, "electric" => 50, "grass" => 50, "ground" => 0, "flying" => 200 },
      "grass" => { "fire" => 50, "water" => 200, "grass" => 50, "poison" => 50, "ground" => 200, "flying" => 50, "bug" => 50,
                   "rock" => 200, "steel" => 50 },
      "ice" => { "fire" => 50, "water" => 50, "grass" => 200, "ice" => 50, "ground" => 200, "flying" => 200, "steel" => 50 },
      "fighting" => { "normal" => 200, "ice" => 200, "poison" => 50, "flying" => 50, "psychic" => 50, "bug" => 50, "rock" => 200,
                      "ghost" => 0, "dark" => 200, "steel" => 200 },
      "poison" => { "grass" => 200, "poison" => 50, "ground" => 50, "rock" => 50, "ghost" => 50, "steel" => 0 },
      "ground" => { "fire" => 200, "electric" => 200, "grass" => 50, "poison" => 200, "flying" => 0, "bug" => 50, "rock" => 200,
                    "steel" => 200 },
      "flying" => { "electric" => 50, "grass" => 200, "fighting" => 200, "bug" => 200, "rock" => 50, "steel" => 50 },
      "psychic" => { "fighting" => 200, "poison" => 200, "psychic" => 50, "dark" => 0, "steel" => 50 },
      "bug" => { "fire" => 50, "grass" => 200, "fighting" => 50, "poison" => 50, "flying" => 50, "psychic" => 200, "ghost" => 50,
                 "dark" => 200, "steel" => 50 },
      "rock" => { "fire" => 200, "ice" => 200, "fighting" => 50, "ground" => 50, "flying" => 200, "bug" => 200, "steel" => 50 },
      "ghost" => { "normal" => 0, "psychic" => 200, "ghost" => 200, "dark" => 50 },
      "dark" => { "fighting" => 50, "psychic" => 200, "ghost" => 200, "dark" => 50 },
      "steel" => { "fire" => 50, "water" => 50, "electric" => 50, "ice" => 200, "rock" => 200, "steel" => 50 }
    }.freeze

    AFFINITIES = %w[weak resist immune absorb].freeze

    # Some types shrug off a status, as in the games: poison and steel
    # can't be poisoned, electric can't be paralysed.
    STATUS_IMMUNITIES = { "poison" => %w[poison], "steel" => %w[poison], "electric" => %w[paralyze] }.freeze

    module_function

    # The percent a move of this type does to the target, or :absorb.
    def effectiveness(type, target)
      return 100 unless type

      affinity = target.fetch("affinities", {})[type]
      return :absorb if affinity == "absorb"
      return 0 if affinity == "immune"

      percent = target.fetch("types", []).reduce(100) { |p, defending| p * CHART.fetch(type).fetch(defending, 100) / 100 }
      # A character's job type never makes them untouchable: what the
      # chart calls no effect is a resistance.
      percent = 50 if percent.zero? && target["immune_as_resist"]
      percent *= 2 if affinity == "weak"
      percent /= 2 if affinity == "resist"
      percent
    end

    def status_immune?(target, kind)
      target.fetch("types", []).any? { |t| STATUS_IMMUNITIES.fetch(t, []).include?(kind) }
    end
  end
end
