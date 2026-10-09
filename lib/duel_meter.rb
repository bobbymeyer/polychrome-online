# frozen_string_literal: true

require_relative "battle/rng"

# A duel's meter (Duel; docs/ODA.md): pure, like the battle engine. Three
# rounds; each round both duellists swing once at the same target, a spot on
# a meter LENGTH units long, and score its points. The spot moves every
# round and its bands narrow: a 1-unit perfect in the middle (3), good on
# either side of it (2), okay beyond that (1), anywhere else a miss (0).
# Where the spot is each round comes from the duel's seed, so it's the same
# for everyone, every time.
module DuelMeter
  LENGTH = 300
  ROUNDS = 3
  # Half the perfect spot: it is one unit wide.
  PERFECT = 0.5
  # How far good and okay reach beyond the band inside them, each round.
  GOOD = [ 5, 4, 3 ].freeze
  OKAY = [ 10, 7, 4 ].freeze
  POINTS = { "perfect" => 3, "good" => 2, "okay" => 1, "miss" => 0 }.freeze
  # How long the needle takes across the meter, one way (the view's pace).
  SWEEP_MS = 1400
  SIDES = %w[character gm].freeze

  module_function

  # Round n's target: { "round", "center", "good", "okay" }, the bands'
  # widths beyond the band inside them. A spot never sits where its bands
  # would run off the meter.
  def zone(seed, round)
    raise ArgumentError, "a duel has rounds 1 to #{ROUNDS}" unless round.between?(1, ROUNDS)

    good = GOOD.fetch(round - 1)
    okay = OKAY.fetch(round - 1)
    margin = (PERFECT + good + okay).ceil + 5
    rng = Battle::Rng.new(Battle::Rng.seed_state(seed) + (round * 7919))
    { "round" => round, "center" => margin + rng.int(LENGTH - (2 * margin)), "good" => good, "okay" => okay }
  end

  # Where a swing stopped, read against the round's target.
  def grade(zone, position)
    off = (position.to_f - zone["center"]).abs
    if off <= PERFECT then "perfect"
    elsif off <= PERFECT + zone["good"] then "good"
    elsif off <= PERFECT + zone["good"] + zone["okay"] then "okay"
    else "miss"
    end
  end

  def points(grade) = POINTS.fetch(grade)

  # A swing's position as the meter reports it: on the meter, to a tenth.
  def position(value)
    number = Float(value, exception: false)
    raise ArgumentError, "a swing stops somewhere on the meter" unless number&.finite? && number.between?(0, LENGTH)

    number.round(1)
  end

  # Each side's total so far, from rounds of { "swings" => { side => { "points" } } }.
  def totals(rounds)
    SIDES.to_h { |side| [ side, rounds.sum { |r| r.dig("swings", side, "points").to_i } ] }
  end

  # Who won: a side, or "satisfaction" when the totals are level (both win).
  def result(totals)
    a, b = totals.values_at(*SIDES)
    return "satisfaction" if a == b

    a > b ? "character" : "gm"
  end
end
