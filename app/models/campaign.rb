# frozen_string_literal: true

# A party's run through a world (docs/HANDOFF.md §4, campaign layer): its
# characters, map, messages, clocks and secrets, and the party's money.
# What a campaign does is told in slices, one story each: its bag, shopping,
# town services and rest, travel, checks, what it has learned about
# monsters and the jobs it has open (app/models/campaign/).
class Campaign < ApplicationRecord
  include Timekeeping
  include Mapping
  include Controls
  include LineLists

  belongs_to :world
  belongs_to :gm, class_name: "User", optional: true
  belongs_to :current_node, class_name: "MapNode", optional: true
  # The map the stage shows while the GM has it there (stage_view "map"); nil: the one the party is on.
  belongs_to :shown_map, class_name: "Map", optional: true

  # In the order they go when the campaign does: the foreign keys are plain,
  # so whatever points at something goes before it (spec/models/deleting_spec.rb).
  before_destroy(prepend: true) { update_columns(current_node_id: nil) if current_node_id }
  has_many :messages, dependent: :delete_all # at battles and characters
  has_many :field_uses, dependent: :destroy # at characters
  has_many :scenes, dependent: :destroy # at places and their modes
  # The scene on the stage right now, if one is (Scene#start!).
  belongs_to :staged_scene, class_name: "Scene", optional: true

  # The beat on the stage right now, if a scene is.
  def staged_beat
    staged_scene&.current_beat
  end
  has_many :clocks, dependent: :delete_all # at modes
  has_many :secrets, dependent: :delete_all # at places and NPCs
  has_many :rumours, dependent: :destroy # at places and secrets
  has_many :flags, dependent: :delete_all
  has_many :inventories, dependent: :delete_all
  has_many :battles, class_name: "BattleRecord", dependent: :destroy do
    # Those still being fought.
    def under_way = where(status: "input")
  end
  # The party, in the order it was made: everything that lists it keeps to that.
  has_many :characters, -> { order(:created_at) }, dependent: :destroy do # at places (home)
    # With what their stats need loaded (Character#stats).
    def with_stats = includes(:job, :character_jobs, equipment_slots: :item)
  end
  has_many :npcs, dependent: :destroy # at places
  has_many :map_edges, dependent: :destroy
  has_many :map_nodes, dependent: :destroy # at locations
  has_many :maps, dependent: :destroy # at nodes
  has_many :map_links, dependent: :destroy
  has_many :locations, dependent: :destroy

  include Bag, Shopping, Services, Travelling, Ways, Checks, Belonging, Limits, Moment, Remarks, Moves, MonsterNotes, JobRewards, Payoffs, Happenings, Rumours, Deeds, Defeat, Broadcasts

  # The campaign's dice: one seeded RNG, stored here like a battle's, for
  # everything outside a battle (encounters on the road, checks, what
  # happens overnight). Every roll goes through #roll or #roll_with, which
  # keep where the dice got to: a state left unsaved rolls the same again.
  before_create { self.rng = Random.new_seed % 2**32 if rng.zero? }

  # Roll with the dice (a Battle::Rng); returns what the block does.
  #   roll { |dice| dice.d100(40) }
  def roll
    dice = Battle::Rng.new(rng)
    result = yield dice
    update!(rng: dice.state)
    result
  end

  # Hand the dice's state to a pure step that returns the next state and
  # what it rolled (Pointcrawl, Battle::Field); returns what it rolled.
  #   roll_with { |state| Pointcrawl::Encounters.roll(state, entries, "dangerous") }
  def roll_with
    next_state, result = yield rng
    update!(rng: next_state)
    result
  end

  # The GM's choice of music: a kind of scene's track, one of the world's
  # tracks by name ("track:12"), or silence. Nil follows the
  # scene (each page plays its own).
  MUSIC_CHOICES = (World::MUSIC + %w[silence]).freeze
  normalizes :music, with: ->(value) { value.presence }
  validate :music_is_heard, if: :music

  validates :name, presence: true
  validates :gil, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Tell the table what happened, in the game's own voice: "The party
  # rests.", "Found a Potion in the Ossuary." cue: a sound or picture for it
  # ("treasure", "check"); data: what the page needs to show it.
  def narrate(body, **details)
    messages.create!(kind: "system", body: body, **details)
  end

  def battle_on? = current_battle.present?

  # The battle the table points at: the newest one still being fought.
  def current_battle
    battles.under_way.order(created_at: :desc, id: :desc).first
  end

  # The kind of scene the party is in, for its music: a dungeon being
  # explored, a town, or the open road.
  def scene
    return "dungeon" if dungeon_in_progress

    # A place in a mode has its own music (Location#mode_music).
    moded = current_node&.mode_music
    return moded if moded

    current_node&.location&.town? ? "town" : "field"
  end

  # The level a party starts at, and a new player's character joins at: the
  # party's lowest, so nobody walks in ahead of the others.
  FIRST_LEVEL = 5

  def newcomer_level
    characters.minimum(:level) || FIRST_LEVEL
  end

  # A player's own new character: theirs from the start, at the party's
  # lowest level, their job level following it. Unsaved, for the caller to
  # save (the join page signs a guest in first, once it's valid).
  def newcomer(attrs, user: nil)
    characters.new(attrs).tap do |character|
      character.user = user
      character.starting_level = newcomer_level
      character.starting_job_level = nil
    end
  end

  # The code behind the invite link and the shared screen's QR code: made
  # with the campaign, and replaced when the GM wants to shut old links out.
  before_create { self.join_code ||= Campaign.fresh_join_code }

  def self.fresh_join_code = SecureRandom.alphanumeric(6).upcase

  def new_join_code!
    update!(join_code: Campaign.fresh_join_code)
    join_code
  end

  # Those still on their feet, in the party's order, with what their stats need.
  def conscious_characters
    characters.with_stats.select(&:conscious?)
  end

  # The choice the table is deciding, if any (Message#settle!).
  def open_choice
    messages.where(kind: "choice", settled: nil).order(:id).last
  end

  # Sets a flag (Flag), making it if it's new: set_flag!("met_the_king", "yes").
  # With a block, the new value is made from the old (nil for a new flag).
  def set_flag!(key, value = nil)
    flag = flags.find_or_initialize_by(key: key)
    flag.update!(value: block_given? ? yield(flag.value) : value)
    flag
  end

  # What's remembered for a request is forgotten with the record's state.
  def reload(*)
    @story_avoid = nil
    super
  end

  # An amount in the world's money: "150 gil", "150 crowns".
  delegate :money, to: :world

  def music_is_heard
    return if world.music_choice?(music)

    errors.add(:music, "isn't one of the world's tracks")
  end
end
