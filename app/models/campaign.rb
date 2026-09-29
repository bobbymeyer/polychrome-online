# frozen_string_literal: true

# A party's run through a world (docs/HANDOFF.md §4, campaign layer): its
# characters, map, messages, clocks and secrets, and the party's money.
# What a campaign does is told in slices, one story each: its bag, shopping,
# town services and rest, travel, checks, what it has learned about
# monsters and the jobs it has open (app/models/campaign/).
class Campaign < ApplicationRecord
  include Timekeeping

  belongs_to :world
  belongs_to :gm, class_name: "User", optional: true
  belongs_to :current_node, class_name: "MapNode", optional: true

  # In the order they go when the campaign does: the foreign keys are plain,
  # so whatever points at something goes before it (spec/models/deleting_spec.rb).
  before_destroy(prepend: true) { update_columns(current_node_id: nil) if current_node_id }
  has_many :messages, dependent: :delete_all # at battles and characters
  has_many :field_uses, dependent: :destroy # at characters
  has_many :scenes, dependent: :destroy # at places and their modes
  has_many :clocks, dependent: :delete_all # at modes
  has_many :secrets, dependent: :delete_all # at places and NPCs
  has_many :rumours, dependent: :destroy # at places, deeds and secrets
  has_many :deeds, dependent: :delete_all
  has_many :flags, dependent: :delete_all
  has_many :inventories, dependent: :delete_all
  has_many :battles, class_name: "BattleRecord", dependent: :destroy
  has_many :characters, dependent: :destroy # at places (home)
  has_many :npcs, dependent: :destroy # at places
  has_many :map_edges, dependent: :destroy
  has_many :map_nodes, dependent: :destroy # at locations
  has_many :locations, dependent: :destroy

  include Bag, Shopping, Services, Travelling, Checks, MonsterNotes, JobRewards, Overnight, Deeds, Defeat, Broadcasts

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

  # The GM's choice of music: a scene's track or silence. Nil follows the
  # scene, so a town sounds like a town and a dungeon like a dungeon.
  MUSIC_CHOICES = (World::MUSIC + %w[silence]).freeze
  normalizes :music, with: ->(value) { value.presence }
  validates :music, inclusion: { in: MUSIC_CHOICES }, allow_nil: true

  validates :name, presence: true
  validates :gil, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Tell the table what happened, in the game's own voice: "The party
  # rests.", "Found a Potion in the Ossuary." cue: a sound or picture for it
  # ("treasure", "check"); data: what the page needs to show it.
  def narrate(body, **details)
    messages.create!(kind: "system", body: body, **details)
  end

  def battle_on?
    battles.where(status: "input").exists?
  end

  # The battle the table points at: the newest one still being fought.
  def current_battle
    battles.where(status: "input").order(created_at: :desc, id: :desc).first
  end

  # The kind of scene the party is in, for its music: a dungeon being
  # explored, a town, or the open road.
  def scene
    return "dungeon" if dungeon_in_progress

    # A place in a mode has its own music (Location#switch_mode!).
    moded = current_node&.location&.current_mode&.music
    return moded if moded

    current_node&.location&.town? ? "town" : "field"
  end

  # The level a party starts at, and a new player's character joins at: the
  # party's lowest, so nobody walks in ahead of the others.
  FIRST_LEVEL = 5

  def newcomer_level
    characters.minimum(:level) || FIRST_LEVEL
  end

  # The code behind the invite link and the shared screen's QR code: made
  # when first asked for, and replaced when the GM wants to shut old links out.
  def join_code!
    join_code || new_join_code!
  end

  def new_join_code!
    update!(join_code: SecureRandom.alphanumeric(6).upcase)
    join_code
  end

  # The choice the table is deciding, if any (Message#settle!).
  def open_choice
    messages.where(kind: "choice", settled: nil).order(:id).last
  end

  # An amount in the world's money: "150 gil", "150 crowns".
  def money(amount)
    "#{amount} #{world.word('currency')}"
  end
end
