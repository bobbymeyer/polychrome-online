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
  belongs_to :campaign, optional: true
  has_many :battle_actions, -> { order(:position) }, foreign_key: :battle_id, inverse_of: :battle, dependent: :destroy
  has_many :battle_events, -> { order(:position) }, foreign_key: :battle_id, inverse_of: :battle, dependent: :delete_all

  validates :name, presence: true
  validates :campaign, presence: true, on: :create
  validates :playback_speed, inclusion: { in: SPEEDS }
  validates :input_seconds, inclusion: { in: INPUT_TIMERS }

  # Start a battle for some of a campaign's characters.
  #   encounter: { "goblin" => 3, "wolf" => 1 }
  def self.start!(campaign:, characters:, name:, encounter:, seed: nil, escapable: true, input_seconds: nil)
    seed = seed.presence&.to_i || Random.new_seed % 2**31
    party = characters.map(&:battle_spec)
    state = campaign.world.battle(seed: seed, party: party, monsters: encounter, escapable: escapable)
    create!(world: campaign.world, campaign: campaign, name: name, seed: seed, initial_state: state, state: state,
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
      settle!(events) if over?
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

  # Characters in this battle, keyed by unit id.
  def characters_by_unit
    ids = party.filter_map { |u| Character.from_battle_unit(u["id"]) }
    campaign.characters.where(id: ids).index_by(&:battle_unit_id)
  end

  def set_speed!(speed)
    update!(playback_speed: speed)
    broadcast_replace_to self, target: "battle_playback", partial: "battles/playback", locals: { battle: self }
  end

  private

  # When the battle ends, what happened is written back to the campaign:
  # HP/MP always; on victory, EXP split among the standing, ABP to each
  # standing character's current job, gil, and the dropped items. Runs
  # once, inside the transaction of the action that ended the battle.
  def settle!(events)
    return if settlement

    characters = characters_by_unit
    party.each do |unit|
      characters[unit["id"]]&.update!(hp: unit["hp"], mp: unit["mp"])
    end

    summary = { "result" => status, "gil" => 0, "drops" => [], "members" => [] }
    victory = events.find { |e| e["type"] == "victory" }
    if victory
      rewards = victory["rewards"]
      standing = party.select { |u| u["hp"].positive? }.filter_map { |u| characters[u["id"]] }
      exp_share = standing.empty? ? 0 : rewards["exp"].to_i / standing.size
      standing.each do |character|
        summary["members"] << { "name" => character.name }.merge(character.gain!(exp: exp_share, abp: rewards["abp"].to_i))
      end

      campaign.increment!(:gil, rewards["gil"].to_i)
      summary["gil"] = rewards["gil"].to_i
      items = world.items.where(slug: victory["drops"]).index_by(&:slug)
      victory["drops"].each do |slug|
        next unless (item = items[slug])

        campaign.add_item!(item)
        summary["drops"] << item.name
      end
    end
    update!(settlement: summary)
  end

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
