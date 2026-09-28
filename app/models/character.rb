# frozen_string_literal: true

# A player's character (docs/HANDOFF.md §4): a level from EXP, a current job,
# progress in every job they've held, equipment from the party bag, and
# cross-job abilities in the current job's free slots.
#
# Stats are never stored. They are derived on demand by the pure
# Stats::Growth (level -> base) and Stats::Derivation (base x job +
# equipment + innates) modules.
#
# What a character does is in slices (app/models/character/): progression,
# abilities and jobs, equipment, background and their battle unit.
class Character < ApplicationRecord
  include Portrayed
  include ArtSubject
  include Colourable

  include Progression, Abilities, Equipment, Background, InBattle

  SLOTS = %w[weapon shield head body accessory].freeze

  belongs_to :campaign
  belongs_to :user, optional: true
  belongs_to :job
  belongs_to :home_node, class_name: "MapNode", optional: true
  has_many :character_jobs, dependent: :destroy
  has_many :ability_slots, -> { order(:position) }, dependent: :destroy
  has_many :equipment_slots, dependent: :destroy
  has_many :messages, as: :speaker, dependent: :destroy
  has_many :whispers_received, class_name: "Message", foreign_key: :recipient_id, dependent: :destroy

  # Creation-only inputs: the level and current-job level to start at.
  attribute :starting_level, :integer
  attribute :starting_job_level, :integer
  attribute :starting_gear, :boolean, default: true

  before_validation :apply_starting_level, on: :create
  before_validation { self.level = Stats::Growth.level_for_exp(exp.to_i) }
  after_create :start_in_job, :outfit

  # Why they're here, in their own words: one line, on their card, and
  # their battle cry when a desperation move comes (Battle::Resolver).
  MOTIVE_LENGTH = 140
  normalizes :motive, with: ->(line) { line.to_s.strip.delete_prefix("“").delete_prefix('"').delete_suffix("”").delete_suffix('"').strip.presence }
  validates :motive, length: { maximum: MOTIVE_LENGTH }

  validates :name, presence: true
  validates :exp, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :starting_level, numericality: { in: 1..Stats::Growth::MAX_LEVEL }, allow_nil: true, on: :create
  validates :starting_job_level, numericality: { in: 0..Stats::Growth::MAX_JOB_LEVEL }, allow_nil: true, on: :create
  validate :job_from_the_campaign_world
  validate :from_the_setting
  validate :job_open_in_the_campaign, on: :create

  delegate :world, to: :campaign

  # --- stats ---------------------------------------------------------------

  # Each stage of the derivation, for the character sheet: level base, then
  # with the job's multipliers, then equipment, then innates (the total).
  def stat_stages
    @stat_stages ||= begin
      base = Stats::Growth.base_stats(level)
      gear = equipped_items.map(&:to_equipment)
      {
        base: base,
        job: Stats::Derivation.derive(base: base, job: job.to_derivation),
        equipment: Stats::Derivation.derive(base: base, job: job.to_derivation, equipment: gear),
        total: Stats::Derivation.derive(base: base, job: job.to_derivation, equipment: gear, passives: job.passives)
      }
    end
  end

  def stats
    stat_stages[:total]
  end

  def current_hp
    hp.nil? ? stats["max_hp"] : hp.clamp(0, stats["max_hp"])
  end

  def current_mp
    mp.nil? ? stats["max_mp"] : mp.clamp(0, stats["max_mp"])
  end

  def conscious?
    current_hp.positive?
  end

  def reload(*)
    @stat_stages = nil
    @masteries = nil
    super
  end

  # Without a portrait of their own, a character is drawn as their job.
  def fallback_portrait_entry
    job
  end
end
