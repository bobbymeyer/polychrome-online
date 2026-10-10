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
#
# Its rounds and timers, what it writes back when it ends, and the GM's
# overrides in engine terms are slices (app/models/battle_record/).
class BattleRecord < ApplicationRecord
  self.table_name = "battles"

  include Rounds, Settlement, Overrides

  SPEEDS = [ 1, 2, 4 ].freeze
  INPUT_TIMERS = [ nil, 30, 60, 120 ].freeze
  DEFAULT_TIMER = 60

  def self.model_name
    @model_name ||= ActiveModel::Name.new(self, nil, "Battle")
  end

  belongs_to :world
  belongs_to :campaign, optional: true
  has_many :battle_actions, -> { order(:position) }, foreign_key: :battle_id, inverse_of: :battle, dependent: :destroy
  has_many :battle_events, -> { order(:position) }, foreign_key: :battle_id, inverse_of: :battle, dependent: :delete_all
  # The table's lines about it stay, no longer linked.
  has_many :messages, foreign_key: :battle_id, inverse_of: :battle, dependent: :nullify

  validates :name, presence: true
  validates :campaign, presence: true, on: :create
  validates :playback_speed, inclusion: { in: SPEEDS }
  validates :input_seconds, inclusion: { in: INPUT_TIMERS }

  # Start a battle for some of a campaign's characters.
  #   encounter: { "goblin" => 3, "wolf" => 1 }
  # antagonists: the campaign's NPCs who fight in it (Npc#battle_spec).
  # names: { "dark_mage" => "Sten Pike" }, a name for the first of a kind.
  # room: the dungeon room this fight is for, dealt with when it is won (Settlement).
  # field: the room's field, in stages (Battle::Conditions): the water rising.
  # waves: more fights after the first, { slug => count } each, coming on as the field clears.
  def self.start!(campaign:, characters:, name:, encounter:, seed: nil, escapable: true, input_seconds: nil, boss: false, terrain: nil,
                  antagonists: [], names: {}, room: nil, prelude_said: false, field: nil, waves: [])
    seed = seed.presence&.to_i || Random.new_seed % 2**31
    party = characters.map(&:battle_spec)
    raise Refusal, "#{antagonists.find(&:defeated?).name} was defeated for good" if antagonists.any?(&:defeated?)

    state = campaign.world.battle(seed: seed, party: party, monsters: encounter, escapable: escapable, items: campaign.battle_items,
                                  terrain: terrain.presence, extra_enemies: antagonists.map(&:battle_spec), field: field.presence,
                                  waves: Array(waves).map(&:to_h).reject(&:empty?))
    names.each do |slug, named|
      unit = state["units"].find { |u| u["side"] == "enemy" && u.dig("image", "slug") == slug }
      unit.merge!("name" => named, "named" => true) if unit # its own name: kept through its phases
    end
    monsters = campaign.world.monsters.where(slug: encounter.keys).index_by(&:slug)
    battle = create!(world: campaign.world, campaign: campaign, name: name, seed: seed, initial_state: state, state: state,
                     input_seconds: input_seconds, auto_units: characters.reject(&:user_id).map(&:battle_unit_id), room: room, prelude_said: prelude_said,
                     boss: boss || antagonists.any? || monsters.each_value.any?(&:boss?))
    battle.open_round!
    campaign.update!(controls: "talk") if campaign.controls == "battle" # the setup form has done its job
    against = antagonists.map(&:name) + encounter.map { |slug, count| "#{count} × #{monsters[slug]&.name || slug}" }
    more = Array(waves).reject(&:blank?).size
    battle.announce!("#{name} begins: #{characters.map(&:name).to_sentence} against #{against.to_sentence}#{", and #{more} more #{more == 1 ? 'wave' : 'waves'} behind them" if more.positive?}.")
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
    campaign&.narrate(body, battle: self)
  end

  # The battle's numbers so far, from its replay log (Battle::Report).
  def report = Battle::Report.build(initial_state, battle_events.map(&:payload), state)

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

    before = state
    update!(status: "abandoned", deadline_at: nil)
    announce!("#{name} was called off.")
    # Not a resolver action, but everyone in the fight hears it the same way: one beat, which
    # takes their command panel to the results (a page that's over doesn't take another beat).
    broadcast_beat(before, [ { "type" => "abandoned" } ], next_position(:battle_actions))
  end

  # The state as the app reads it (BattleState): a fresh one each time, since the state moves on.
  def field = BattleState.new(state)

  delegate :units, :unit, :awaiting_input, to: :field

  # The party's own: the characters. Guests fight beside them (Battle
  # "add_unit") but take no seat and share no rewards.
  def party
    units.select { |u| u.party? && !u.guest? }
  end

  def enemies
    units.select(&:enemy?)
  end

  # Apply one action through the resolver, persist it with its events, and
  # broadcast the beat; then play on with whatever the battle does by
  # itself (#play_on!). Raises Battle::InvalidAction (nothing is saved).
  # `if_round` makes the action a no-op (returns nil) if the battle has
  # moved on, which is how a stale input timer is ignored.
  # Returns the state before the action and its events.
  def apply!(action, actor:, if_round: nil)
    played = play!(action, actor: actor, if_round: if_round) or return nil
    play_on! if opened_round?(played)
    played
  end

  # A round nobody can choose anything in (everyone asleep, confused or
  # stopped) runs at once, not after the timer, and so on until someone
  # can choose again. Bounded, in case a battle never lets anyone.
  QUIET_ROUNDS = 10

  # The bosses in this fight, for their entrance: the monsters marked as
  # bosses, or, in a dungeon's boss room, the strongest there.
  # The boss's own music, if it has any (Monster#music): the first boss in the fight with a track of its
  # own, an antagonist's entry counted. Else the boss slot, or the battle's.
  def music_choice
    villains = enemies.filter_map { |u| u.npc_id && campaign&.npcs&.find_by(id: u.npc_id)&.monster }
    own = (villains + boss_monsters.to_a).find { |monster| monster.music.present? }
    own&.music || (boss? ? "boss" : "battle")
  end

  # The Bestiary entries behind the bosses, for their entrance: an antagonist's entry first, else the boss monsters.
  def boss_entries
    villains = enemies.filter_map { |u| u.npc_id && campaign&.npcs&.find_by(id: u.npc_id)&.monster }
    villains.presence || boss_monsters.to_a
  end

  def boss_monsters
    return Monster.none unless boss?

    slugs = enemies.map(&:image_slug).uniq
    marked = world.monsters.where(slug: slugs, boss: true)
    marked.exists? ? marked : world.monsters.where(slug: slugs).order(level: :desc).limit(1)
  end

  # What the bosses are called in this fight: the antagonists in it, or a
  # named boss (Roz Tennant, who never came out) by their own name, not
  # their kind's.
  def boss_names
    villains = enemies.select(&:npc_id)
    return villains.map(&:name) if villains.any?

    boss_monsters.map do |monster|
      units = enemies.select { |u| u.image_slug == monster.slug }
      units.map(&:name).find { |name| !name.start_with?(monster.name) } || monster.name
    end
  end

  # The bosses as they stand on the field: the antagonists, or every unit of the boss monsters.
  def boss_units
    villains = enemies.select(&:npc_id)
    return villains if villains.any?

    slugs = boss_monsters.pluck(:slug)
    enemies.select { |u| slugs.include?(u.image_slug) }
  end

  # Beating a boss means knocking it out. One that left the field (sent off, or fled) got away:
  # the fight is won, but the place isn't cleared and the boss hasn't fallen.
  def bosses_beaten? = boss_units.none?(&:gone?)

  # Whether any enemy fell: a "victory" over enemies who all left is them getting away.
  def enemies_fell? = enemies.any? { |u| !u.gone? }

  RESULT_LINES = { "victory" => "Victory!", "defeat" => "The party has fallen.", "fled" => "The party got away.",
                   "abandoned" => "Called off. Nothing came of it." }.freeze

  # How it ended, in a line (the results panel, the log).
  def result_line
    return "They got away." if status == "victory" && !enemies_fell?

    RESULT_LINES.fetch(status, status.humanize)
  end

  def replay
    Battle::Replay.run(initial_state, battle_actions.map(&:payload))
  end

  # Characters in this battle, keyed by unit id.
  def characters_by_unit
    ids = party.filter_map(&:character_id)
    campaign.characters.where(id: ids).index_by(&:battle_unit_id)
  end

  def set_speed!(speed)
    update!(playback_speed: speed)
    broadcast_replace_to self, target: "battle_playback", partial: "battles/playback", locals: { battle: self }
  end

  # Every seat's command panel asks for itself again (battle_player_controller#panelChanged): a player
  # came back, so the GM's rows say so. A seat mid-choice keeps its menu.
  def refresh_panels
    Turbo::StreamsChannel.broadcast_action_to(self, action: :battle_panel, target: "battle_beats")
  end

  # Whether the last round ran without this unit's choice (the clock ran out, or the GM ran it):
  # the player's panel says so, since their choice was refused with the round already gone.
  def ran_without?(unit_id)
    ran = battle_events.where(kind: %w[timeout gm_override]).order(:position).last
    return false unless ran && Array(ran.payload["defaulted"]).include?(unit_id)

    battle_events.where(kind: "round_start").order(:position).last&.position.to_i > ran.position
  end

  private

  # One beat: the action through the resolver inside the lock, its events
  # logged, the clock moved on, and the beat broadcast. Returns [before,
  # events], or nil if `if_round` says the battle has moved on.
  def play!(action, actor:, if_round: nil)
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
    # Settling saves again, so by the commit the status change isn't the last one (refresh_table_header's
    # condition misses it): the table and the Ready buttons hear it's over from here.
    refresh_table_header if over? && before["status"] == "input"
    opened_round?([ before, events ]) ? open_round! : resume_clock!
    broadcast_beat(before, events, record.position)
    [ before, events ]
  end

  # Whether a beat ([before, events]) opened a new round of a battle still on.
  def opened_round?((before, _events)) = !over? && round != before["round"]

  # What the battle does by itself once a round opens, beat by beat: the
  # units on auto choose (#auto_command), and a round nobody can choose in
  # runs at once. Each can open another round, which goes round again.
  def play_on!
    quiet = 0
    loop do
      auto = auto_command
      played = begin
        play!(auto, actor: "gm", if_round: round) if auto
      rescue Battle::InvalidAction
        nil # someone sat down and chose for one of them first; the timer or the GM covers the rest
      end
      next if played && opened_round?(played)
      break if over? || awaiting_input.any? || (quiet += 1) > QUIET_ROUNDS

      played = play!({ "type" => "timeout" }, actor: "gm", if_round: round)
      break unless played && opened_round?(played)
    end
  end

  # The table's "… is on" button follows the current battle for everyone,
  # and the campaign's documents list it. Only when it starts or ends: a
  # battle's own beats have their own stream.
  def refresh_table_header
    clear_ready_buttons if over?
    return unless campaign

    Turbo::StreamsChannel.broadcast_replace_to(campaign, :table, target: "table_battle",
                                               partial: "campaigns/tables/current_battle", locals: { campaign: campaign })
    campaign.table_changed # where next waits for the fight
    campaign.refresh_pages
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
