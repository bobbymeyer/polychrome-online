# frozen_string_literal: true

# A player's character (docs/HANDOFF.md §4): a level from EXP, a current job,
# progress in every job they've held, equipment from the party bag, and
# cross-job abilities in the current job's free slots.
#
# Stats are never stored. They are derived on demand by the pure
# Stats::Growth (level -> base) and Stats::Derivation (base x job +
# equipment + innates) modules.
class Character < ApplicationRecord
  SLOTS = %w[weapon shield head body accessory].freeze

  belongs_to :campaign
  belongs_to :job
  has_many :character_jobs, dependent: :destroy
  has_many :ability_slots, -> { order(:position) }, dependent: :destroy
  has_many :equipment_slots, dependent: :destroy

  # Creation-only inputs: the level and current-job level to start at.
  attribute :starting_level, :integer
  attribute :starting_job_level, :integer

  before_validation :apply_starting_level, on: :create
  before_validation { self.level = Stats::Growth.level_for_exp(exp.to_i) }
  after_create :start_in_job

  validates :name, presence: true
  validates :exp, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :starting_level, numericality: { in: 1..Stats::Growth::MAX_LEVEL }, allow_nil: true, on: :create
  validates :starting_job_level, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true, on: :create
  validate :job_from_the_campaign_world

  delegate :world, to: :campaign

  # --- progression ---------------------------------------------------------

  def character_job(for_job = job)
    character_jobs.detect { |cj| cj.job_id == for_job.id } || character_jobs.find_or_create_by!(job: for_job)
  end

  def exp_to_next
    Stats::Growth.exp_for_level(level + 1) - exp unless level >= Stats::Growth::MAX_LEVEL
  end

  # Abilities the current job has taught so far: always usable in it.
  def native_abilities
    character_job.learned_abilities
  end

  # Everything learned in any job: what may go into an ability slot.
  def learned_abilities
    character_jobs.includes(job: { job_levels: :ability }).flat_map(&:learned_abilities).uniq
  end

  def slotted_abilities
    ability_slots.includes(:ability).map(&:ability)
  end

  def battle_abilities
    (native_abilities + slotted_abilities).uniq
  end

  # Award EXP and ABP (to the current job). Returns what changed, for the
  # battle's settlement summary.
  def gain!(exp: 0, abp: 0)
    cj = character_job
    before_level = level
    before_learned = cj.learned_abilities
    transaction do
      cj.update!(abp: cj.abp + abp)
      update!(exp: self.exp + exp)
    end
    learned = cj.learned_abilities - before_learned
    {
      "exp" => exp, "abp" => abp,
      "level" => (level > before_level ? [ before_level, level ] : nil),
      "learned" => learned.map(&:name)
    }.compact
  end

  # --- jobs ----------------------------------------------------------------

  # Switch job. Gear the new job can't use goes back to the bag; ability
  # slots beyond the new job's count are cleared.
  def change_job!(new_job)
    unless new_job.world_id == world.id
      errors.add(:job, "must come from #{world.name}")
      raise ActiveRecord::RecordInvalid, self
    end

    transaction do
      character_job(new_job)
      update!(job: new_job)
      equipment_slots.includes(:item).each { |slot| unequip!(slot.slot) unless new_job.equips?(slot.item) }
      ability_slots.where(position: new_job.ability_slots..).destroy_all
    end
  end

  def set_ability_slots!(abilities)
    errors.clear
    abilities = abilities.compact_blank
    learned = learned_abilities
    unlearned = abilities.reject { |a| learned.include?(a) }
    errors.add(:base, "#{unlearned.map(&:name).to_sentence} not learned yet") if unlearned.any?
    errors.add(:base, "#{job.name} has #{job.ability_slots} ability slot(s)") if abilities.size > job.ability_slots
    raise ActiveRecord::RecordInvalid, self if errors.any?

    transaction do
      ability_slots.destroy_all
      abilities.uniq.each_with_index { |ability, i| ability_slots.create!(ability: ability, position: i) }
    end
  end

  # --- equipment -----------------------------------------------------------

  def equipped
    equipment_slots.includes(:item).index_by(&:slot)
  end

  def equipped_items
    equipment_slots.includes(:item).map(&:item)
  end

  # Put an item from the bag into its slot; whatever was there goes back.
  def equip!(item)
    errors.clear
    unless item.equipment? && job.equips?(item)
      errors.add(:base, "#{job.name} can't equip #{item.name}")
      raise ActiveRecord::RecordInvalid, self
    end

    transaction do
      unequip!(item.slot)
      campaign.take_item!(item)
      equipment_slots.create!(slot: item.slot, item: item)
    end
  end

  def unequip!(slot)
    current = equipment_slots.find_by(slot: slot) or return
    transaction do
      campaign.add_item!(current.item)
      current.destroy!
    end
  end

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
    super
  end

  # --- battle --------------------------------------------------------------

  def self.from_battle_unit(unit_id)
    unit_id.to_s.delete_prefix("character_").to_i if unit_id.to_s.start_with?("character_")
  end

  def battle_unit_id
    "character_#{id}"
  end

  # Unit spec for Battle::State.build.
  def battle_spec
    {
      "id" => battle_unit_id,
      "name" => name,
      "stats" => stats,
      "hp" => current_hp,
      "mp" => current_mp,
      "abilities" => battle_abilities.map(&:slug),
      "image" => { "book" => "jobs", "slug" => job.slug }
    }
  end

  private

  def apply_starting_level
    self.exp = Stats::Growth.exp_for_level(starting_level) if starting_level
  end

  def start_in_job
    costs = job.job_levels.map(&:abp)
    character_jobs.create!(job: job, abp: Stats::Growth.abp_for_job_level(starting_job_level.to_i, costs))
  end

  def job_from_the_campaign_world
    errors.add(:job, "must come from #{world.name}") if job && campaign && job.world_id != campaign.world_id
  end
end
