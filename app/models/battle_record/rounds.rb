# frozen_string_literal: true

# Rounds and who plays them: the input timer each round opens with, and the
# units the GM has put on auto.
#
# The clock is never unfair to someone who isn't looking: the first round's
# starts only once every player in the fight has said they're ready (or the
# GM has put them on auto), it stops while a player's idea waits for the
# GM's ruling, and it holds when nobody has the battle open (#watch!), so a
# fight never plays itself out to the end with nobody there.
module BattleRecord::Rounds
  extend ActiveSupport::Concern

  # Added to the input timer when a round opens, to cover the previous
  # round's animation before players can act.
  ANIMATION_GRACE = 8.seconds
  # At least this long to choose once the GM has ruled on an idea.
  AFTER_RULING = 15.seconds
  # Added to a boss fight's first clock, for the boss's entrance.
  BOSS_ENTRANCE = 6.seconds

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

    grace = round > 1 ? ANIMATION_GRACE : (boss? ? BOSS_ENTRANCE : 0)
    update!(deadline_at: Time.current + input_seconds.seconds + grace)
    BattleTimeoutJob.set(wait_until: deadline_at).perform_later(self, round)
  end

  # A player is ready (Battles::ArrivalsController: their Ready button).
  def arrive!(unit_id)
    return if arrived_units.include?(unit_id) || party.none? { |u| u["id"] == unit_id }

    update!(arrived_units: arrived_units | [ unit_id ])
    # The clock starts, or the list of who it's waiting for is one shorter.
    still_coming.empty? ? start_first_clock! : broadcast_countdown
  end

  # The players the first round's clock is waiting for: in the fight and
  # standing, not on auto, and not ready yet.
  def still_coming
    party.select { |u| u["hp"].positive? }.map { |u| u["id"] } - auto_units - arrived_units
  end

  # Everyone's here: the first round's clock starts, on every screen.
  def start_first_clock!
    return unless waiting_for_arrivals?

    open_round!
    broadcast_countdown
  end

  def broadcast_countdown
    broadcast_replace_to self, target: "battle_countdown", partial: "battles/panels/countdown", locals: { battle: self }
  end

  def waiting_for_arrivals?
    input_seconds.present? && !over? && round == 1 && deadline_at.nil?
  end

  # Anyone with the battle open says so now and then (battle_watch_controller,
  # every WATCH_BEAT); gone for longer than WATCHERS_GONE, nobody's watching.
  WATCH_BEAT = 20.seconds
  WATCHERS_GONE = 50.seconds

  def watched? = watched_at.present? && watched_at > WATCHERS_GONE.ago

  # Someone has it in front of them: a clock held for want of anyone
  # watching starts again, with a whole round's time.
  def watch!
    update_column(:watched_at, Time.current)
    return unless held?

    open_round!
    broadcast_countdown
  end

  # The round's time ran out with nobody watching: the round waits.
  def hold_clock!
    update!(deadline_at: nil)
    broadcast_countdown
  end

  # Held: a timed round with no clock running, not because it's waiting
  # for the first round's players to be ready.
  def held? = input_seconds.present? && !over? && deadline_at.nil? && !(round == 1 && still_coming.any?)

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
