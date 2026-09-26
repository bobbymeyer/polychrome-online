# frozen_string_literal: true

# A battle in play (docs/HANDOFF.md §4, session layer).
#
# Named BattleRecord because `Battle` is the pure engine's namespace
# (lib/battle). It reports its model name as "Battle", so routes, params and
# DOM ids still read as battles.
#
# `state` is the resolver's state. `initial_state` plus the ordered actions
# replay to it exactly; `battle_events` is the resolver's output log. All
# rules live in Battle::Resolver: this class only persists, times and
# broadcasts what the resolver decides.
class BattleRecord < ApplicationRecord
  self.table_name = "battles"

  SPEEDS = [ 1, 2, 4 ].freeze
  INPUT_TIMERS = [ nil, 30, 60, 120 ].freeze
  # Added to the input timer when a round opens, to cover the previous
  # round's animation before players can act.
  ANIMATION_GRACE = 8.seconds

  def self.model_name
    @model_name ||= ActiveModel::Name.new(self, nil, "Battle")
  end

  belongs_to :world
  has_many :battle_actions, -> { order(:position) }, foreign_key: :battle_id, inverse_of: :battle, dependent: :destroy
  has_many :battle_events, -> { order(:position) }, foreign_key: :battle_id, inverse_of: :battle, dependent: :delete_all

  validates :name, presence: true
  validates :playback_speed, inclusion: { in: SPEEDS }
  validates :input_seconds, inclusion: { in: INPUT_TIMERS }

  # party:     unit specs (see QuickParty)
  # encounter: { "goblin" => 3, "wolf" => 1 }
  def self.start!(world:, name:, party:, encounter:, seed: nil, escapable: true, input_seconds: nil)
    seed = seed.presence&.to_i || Random.new_seed % 2**31
    state = world.battle(seed: seed, party: party, monsters: encounter, escapable: escapable)
    create!(world: world, name: name, seed: seed, initial_state: state, state: state,
            input_seconds: input_seconds).tap(&:open_round!)
  end

  def over?
    status != "input"
  end

  def units
    state["units"]
  end

  def unit(id)
    units.find { |u| u["id"] == id }
  end

  def party
    units.select { |u| u["side"] == "party" }
  end

  def awaiting_input
    Battle::State.awaiting_input(state)
  end

  # Apply one action through the resolver, persist it with its events, and
  # broadcast the beat. Raises Battle::InvalidAction (nothing is saved).
  # `if_round` makes the action a no-op (returns nil) if the battle has
  # moved on, which is how a stale input timer is ignored.
  def apply!(action, actor:, if_round: nil)
    before = events = nil
    with_lock do
      return nil if if_round && (round != if_round || over?)

      before = state
      after, events = Battle::Resolver.apply(before, action)
      record = battle_actions.create!(position: next_position(:battle_actions), actor: actor,
                                      payload: Battle::State.normalize(action))
      log_events(record, events)
      self.state = after
      self.status = after["status"]
      self.round = after["round"]
      self.deadline_at = nil if over?
      save!
    end
    open_round! if !over? && round != before["round"]
    broadcast_beat(before, events)
    [ before, events ]
  end

  # Start the input timer for the current round, if this battle has one.
  def open_round!
    return unless input_seconds && !over?

    update!(deadline_at: Time.current + input_seconds.seconds + (round > 1 ? ANIMATION_GRACE : 0))
    BattleTimeoutJob.set(wait_until: deadline_at).perform_later(self, round)
  end

  def replay
    Battle::Replay.run(initial_state, battle_actions.map(&:payload))
  end

  def set_speed!(speed)
    update!(playback_speed: speed)
    broadcast_replace_to self, target: "battle_playback", partial: "battles/playback", locals: { battle: self }
  end

  private

  def next_position(association)
    (public_send(association).maximum(:position) || -1) + 1
  end

  def log_events(action_record, events)
    return if events.empty?

    start = next_position(:battle_events)
    now = Time.current
    BattleEvent.insert_all!(events.each_with_index.map do |event, i|
      { battle_id: id, battle_action_id: action_record.id, position: start + i, kind: event["type"],
        payload: event, created_at: now, updated_at: now }
    end)
  end

  # §6: every viewer gets the events plus the state before them, and holds
  # the state after them back until the animation finishes.
  def broadcast_beat(before, events)
    broadcast_append_to self, target: "battle_beats", partial: "battles/beat",
                              locals: { battle: self, before: before, events: events }
  end
end
