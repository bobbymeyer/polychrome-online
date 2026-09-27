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
  DEFAULT_TIMER = 60
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
  def self.start!(campaign:, characters:, name:, encounter:, seed: nil, escapable: true, input_seconds: nil, boss: false, terrain: nil)
    seed = seed.presence&.to_i || Random.new_seed % 2**31
    party = characters.map(&:battle_spec)
    state = campaign.world.battle(seed: seed, party: party, monsters: encounter, escapable: escapable, items: campaign.battle_items,
                                  terrain: terrain.presence)
    battle = create!(world: campaign.world, campaign: campaign, name: name, seed: seed, initial_state: state, state: state,
                     input_seconds: input_seconds, auto_units: characters.reject(&:user_id).map(&:battle_unit_id),
                     boss: boss || campaign.world.monsters.where(slug: encounter.keys, boss: true).exists?)
    battle.open_round!
    battle.announce!("#{name} begins: #{characters.map(&:name).to_sentence} against " \
                     "#{encounter.map { |slug, count| "#{count} × #{campaign.world.monsters.find_by(slug: slug)&.name || slug}" }.to_sentence}.")
    battle.auto_fill!
    battle.call_to_arms
    battle
  end

  # Everyone at the table goes to the battle (docs/DESIGN.md, "The stage"):
  # every game page of the campaign listens on its stage stream, plays the
  # transition and follows.
  def call_to_arms
    return unless campaign

    Turbo::StreamsChannel.broadcast_action_to(campaign, :stage, action: :battle_start, target: "stage",
                                              attributes: { url: Rails.application.routes.url_helpers.battle_path(self), boss: boss? })
  end

  # One callback: after_create_commit and after_update_commit naming the same
  # method would keep only the last.
  after_commit :refresh_table_header, on: %i[create update], if: -> { previously_new_record? || saved_change_to_status? }

  # A system line at the campaign's table, linking back to this battle.
  def announce!(body)
    campaign&.messages&.create!(kind: "system", battle: self, body: body)
  end

  def over?
    status != "input"
  end

  # Plain words for the status, for players.
  STATUS_LABELS = { "input" => "Under way", "victory" => "Won", "defeat" => "Lost", "fled" => "Fled", "abandoned" => "Called off" }.freeze

  def status_label
    STATUS_LABELS.fetch(status) { status.humanize }
  end

  # The GM gives up on a battle that nobody will finish. It didn't happen:
  # no settlement, nobody's HP or items change, and the table stops
  # pointing at it. (Not a resolver action: the fight itself isn't resolved.)
  def call_off!
    return if over?

    update!(status: "abandoned", deadline_at: nil)
    announce!("#{name} was called off.")
  end

  def units
    state["units"]
  end

  def unit(id)
    units.find { |u| u["id"] == id }
  end

  # The party's own: the characters. Guests fight beside them (Battle
  # "add_unit") but take no seat and share no rewards.
  def party
    units.select { |u| u["side"] == "party" && !u["guest"] }
  end

  def enemies
    units.select { |u| u["side"] == "enemy" }
  end

  def awaiting_input
    Battle::State.awaiting_input(state)
  end

  # Apply one action through the resolver, persist it with its events, and
  # broadcast the beat. Raises Battle::InvalidAction (nothing is saved).
  # `if_round` makes the action a no-op (returns nil) if the battle has
  # moved on, which is how a stale input timer is ignored.
  def apply!(action, actor:, if_round: nil)
    before = events = record = nil
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
    campaign&.learn_from!(events, state)
    new_round = !over? && round != before["round"]
    open_round! if new_round
    broadcast_beat(before, events, record.position)
    auto_fill! if new_round
    [ before, events ]
  end

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

  # The bosses in this fight, for their entrance: the monsters marked as
  # bosses, or, in a dungeon's boss room, the strongest there.
  def boss_monsters
    return Monster.none unless boss?

    slugs = enemies.map { |u| u.dig("image", "slug") }.uniq
    marked = world.monsters.where(slug: slugs, boss: true)
    marked.exists? ? marked : world.monsters.where(slug: slugs).order(level: :desc).limit(1)
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
  # Stolen items are the party's however the battle ends.
  def take_stolen_items!
    items = world.items.where(slug: state.fetch("stolen", [])).index_by(&:slug)
    state.fetch("stolen", []).filter_map do |slug|
      next unless (item = items[slug])

      campaign.add_item!(item)
      item.name
    end
  end

  def settle!(events)
    return if settlement

    characters = characters_by_unit
    party.each do |unit|
      characters[unit["id"]]&.update!(hp: unit["hp"], mp: unit["mp"])
    end

    summary = { "result" => status, "gil" => 0, "drops" => [], "members" => [], "used" => use_up_items!,
                "stolen" => take_stolen_items! }
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
    announce!(settlement_line(summary))
  end

  # Items used in battle come out of the bag. Returns { "Potion" => 2 }.
  def use_up_items!
    carried = initial_state.fetch("items", {})
    return {} if carried.empty?

    items = world.items.where(slug: carried.keys).index_by(&:slug)
    carried.each_with_object({}) do |(slug, item), used|
      n = item["count"] - state.dig("items", slug, "count").to_i
      next unless n.positive? && items[slug]

      campaign.use_items!(items[slug], n)
      used[item["name"]] = n
    end
  end

  def settlement_line(summary)
    parts = [ { "victory" => "Victory!", "defeat" => "The party has fallen.", "fled" => "The party got away." }.fetch(summary["result"], "It's over.") ]
    parts << "#{boss_monsters.map(&:name).to_sentence} #{boss_monsters.size > 1 ? 'have' : 'has'} fallen!" if boss? && summary["result"] == "victory"
    parts << "Stole #{summary['stolen'].to_sentence}." if summary["stolen"].present?
    parts << "Used #{summary['used'].map { |name, n| "#{n} × #{name}" }.to_sentence}." if summary["used"].present?
    parts << "#{summary['gil']} gil." if summary["gil"].positive?
    parts << "Found #{summary['drops'].to_sentence}." if summary["drops"].any?
    summary["members"].each do |member|
      parts << "#{member['name']} reached level #{member['level'].last}." if member["level"]
      parts << "#{member['name']} learned #{member['learned'].to_sentence}." if member["learned"].any?
    end
    "#{name}: #{parts.join(' ')}"
  end

  # The table's "… is on" button follows the current battle for everyone.
  def refresh_table_header
    return unless campaign

    Turbo::StreamsChannel.broadcast_replace_to(campaign, :table, target: "table_battle",
                                               partial: "tables/current_battle", locals: { campaign: campaign })
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
  # `position` orders beats: broadcasts can arrive out of order, and the
  # player waits for the one it's missing.
  def broadcast_beat(before, events, position)
    broadcast_append_to self, target: "battle_beats", partial: "battles/beat",
                              locals: { battle: self, before: before, events: events, position: position }
  end
end
