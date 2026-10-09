# frozen_string_literal: true

# A duel (docs/ODA.md): a character against someone the GM plays, outside
# battle. Three rounds; each round both swing once on a meter at the same
# target, which moves and narrows round by round (DuelMeter). Neither swing
# is shown until both are in. The higher total wins, and a character who
# loses is left knocked out; level totals are SATISFACTION, and both win.
# Winning (or satisfaction) ends a coward's shame (Character::Courage).
#
# rounds: one entry a round played or under way:
#   { "swings" => { "character" => { "position", "grade", "points" }, "gm" => {...} } }
class Duel < ApplicationRecord
  STATUSES = %w[on over closed].freeze

  belongs_to :campaign
  belongs_to :character
  belongs_to :npc, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :opponent_name, presence: true

  scope :shown, -> { where(status: %w[on over]) }

  def on? = status == "on"
  def over? = status == "over"

  # The round being played: 1 to DuelMeter::ROUNDS.
  def round
    [ rounds.count { |r| revealed?(r) } + 1, DuelMeter::ROUNDS ].min
  end

  def zone(n = round) = DuelMeter.zone(seed, n)

  def revealed?(entry) = DuelMeter::SIDES.all? { |side| entry.dig("swings", side) }

  # The swings of the round under way (hidden from the other side until both are in).
  def swings = rounds.reject { |r| revealed?(r) }.first&.fetch("swings", {}) || {}

  def swung?(side) = swings.key?(side)

  # The rounds both have swung in, to show everyone.
  def shown_rounds = rounds.select { |r| revealed?(r) }

  def totals = DuelMeter.totals(shown_rounds)

  def name_of(side) = side == "character" ? character.name : opponent_name

  # One side swings in the round under way: where the needle stopped. Once
  # both have, the round is shown to the table; after the last, the duel ends.
  def swing!(side, position)
    raise Refusal, "The duel is over" unless on?
    raise ArgumentError, "unknown side #{side}" unless DuelMeter::SIDES.include?(side)
    raise Refusal, "#{name_of(side)} has swung this round" if swung?(side)

    at = DuelMeter.position(position)
    grade = DuelMeter.grade(zone, at)
    entry = rounds.reject { |r| revealed?(r) }.first
    played = rounds.dup
    if entry
      played[played.index(entry)] = entry.merge("swings" => entry["swings"].merge(side => swing_data(at, grade)))
    else
      played << { "swings" => { side => swing_data(at, grade) } }
    end
    transaction do
      update!(rounds: played)
      reveal!(played.last) if revealed?(played.last)
    end
    campaign.table_changed
  rescue ArgumentError => e
    raise Refusal, e.message
  end

  # The GM puts the result away.
  def close!
    update!(status: "closed") if over?
    campaign.table_changed
  end

  def result_line
    case result
    when "satisfaction" then "SATISFACTION"
    when "character" then "#{character.name} wins"
    when "gm" then "#{opponent_name} wins"
    end
  end

  private

  def swing_data(position, grade) = { "position" => position, "grade" => grade, "points" => DuelMeter.points(grade) }

  def reveal!(entry)
    n = rounds.index(entry) + 1
    said = DuelMeter::SIDES.map { |side| "#{name_of(side)}: #{entry.dig('swings', side, 'grade')} (#{entry.dig('swings', side, 'points')})" }
    campaign.narrate("Round #{n}: #{said.join(' · ')}.")
    finish! if n >= DuelMeter::ROUNDS
  end

  def finish!
    outcome = DuelMeter.result(totals)
    update!(status: "over", result: outcome)
    score = "#{totals['character']} to #{totals['gm']}"
    case outcome
    when "satisfaction"
      campaign.narrate("SATISFACTION. #{character.name} and #{opponent_name}, #{score}: both stood, and both are satisfied.", cue: "cleared")
      character.redeem!
    when "character"
      campaign.narrate("#{character.name} wins the duel, #{score}. #{opponent_name} goes down.", cue: "cleared")
      character.redeem!
    else
      campaign.narrate("#{opponent_name} wins the duel, #{score}. #{character.name} goes down.")
      character.update!(hp: 0)
    end
  end
end
