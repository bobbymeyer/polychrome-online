# frozen_string_literal: true

# Rounds and who plays them: the input timer each round opens with, and the
# units the GM has put on auto.
module BattleRecord::Rounds
  extend ActiveSupport::Concern

  # Added to the input timer when a round opens, to cover the previous
  # round's animation before players can act.
  ANIMATION_GRACE = 8.seconds

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
    auto_fill! if on
  end

  def auto?(unit_id) = auto_units.include?(unit_id)

  # Start the input timer for the current round, if this battle has one.
  def open_round!
    return unless input_seconds && !over?

    update!(deadline_at: Time.current + input_seconds.seconds + (round > 1 ? ANIMATION_GRACE : 0))
    BattleTimeoutJob.set(wait_until: deadline_at).perform_later(self, round)
  end
end
