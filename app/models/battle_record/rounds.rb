# frozen_string_literal: true

# Rounds and who plays them: the input timer each round opens with, and the
# units the GM has put on auto.
#
# The clock is never unfair to someone who isn't looking: the first round's
# starts only once every player in the fight has reached its screen (or the
# GM has put them on auto), and it stops while a player's idea waits for the
# GM's ruling.
module BattleRecord::Rounds
  extend ActiveSupport::Concern

  # Added to the input timer when a round opens, to cover the previous
  # round's animation before players can act.
  ANIMATION_GRACE = 8.seconds
  # At least this long to choose once the GM has ruled on an idea.
  AFTER_RULING = 15.seconds

  # Units the GM has put on auto: nobody is there to play them, so each
  # round they take their default command as it opens (§5, "GM auto for an
  # absent player"). The GM's call, so each one is an override in the log.
  # If everyone still standing is on auto, nothing is filled: the round
  # waits for the GM or the timer, so a battle never plays itself out.
  def auto_fill!
    return if over?

    standing = party.select { |u| u["hp"].positive? }.map { |u| u["id"] }
    return if (standing - auto_units).empty?

    units = awaiting_input & auto_units
    return if units.empty?

    apply!({ "type" => "gm_override", "op" => "auto", "units" => units }, actor: "gm", if_round: round)
  rescue Battle::InvalidAction
    nil # someone sat down and chose for one of them first; the timer or the GM covers the rest
  end

  def set_auto!(unit_id, on)
    return unless party.any? { |u| u["id"] == unit_id }

    update!(auto_units: on ? (auto_units | [ unit_id ]) : (auto_units - [ unit_id ]))
    start_first_clock! # nobody to wait for on auto
    auto_fill! if on
  end

  def auto?(unit_id) = auto_units.include?(unit_id)

  # Start the input timer for the current round, if this battle has one.
  # The first round's waits for everyone to arrive (#arrive!).
  def open_round!
    return unless input_seconds && !over?
    return if round == 1 && still_coming.any?

    update!(deadline_at: Time.current + input_seconds.seconds + (round > 1 ? ANIMATION_GRACE : 0))
    BattleTimeoutJob.set(wait_until: deadline_at).perform_later(self, round)
  end

  # A player has the battle in front of them (Battles::PanelsController).
  def arrive!(unit_id)
    return if arrived_units.include?(unit_id) || party.none? { |u| u["id"] == unit_id }

    update!(arrived_units: arrived_units | [ unit_id ])
    start_first_clock!
  end

  # The players the first round's clock is waiting for: in the fight and
  # standing, not on auto, and not at the battle yet.
  def still_coming
    party.select { |u| u["hp"].positive? }.map { |u| u["id"] } - auto_units - arrived_units
  end

  # Everyone's here: the first round's clock starts, on every screen.
  def start_first_clock!
    return unless waiting_for_arrivals?

    open_round!
    broadcast_replace_to self, target: "battle_countdown", partial: "battles/panels/countdown", locals: { battle: self }
  end

  def waiting_for_arrivals?
    input_seconds.present? && !over? && round == 1 && deadline_at.nil?
  end

  # A player's idea is waiting for the GM's ruling: the clock stops.
  def ruling_pending?
    state["inputs"].any? { |_, cmd| cmd["kind"] == "custom" && !cmd["ruling"] }
  end

  # Once nothing is waiting for a ruling, the clock goes on, with at least
  # AFTER_RULING left to choose in.
  def resume_clock!
    return if deadline_at.nil? || over? || ruling_pending? || deadline_at > AFTER_RULING.from_now

    update!(deadline_at: AFTER_RULING.from_now)
    BattleTimeoutJob.set(wait_until: deadline_at).perform_later(self, round)
  end
end
