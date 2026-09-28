# frozen_string_literal: true

# Jobs and what they teach: the abilities learned in every job held, the
# ones slotted into the current job, mastery, and changing job.
module Character::Abilities
  extend ActiveSupport::Concern

  def character_job(for_job = job)
    character_jobs.detect { |cj| cj.job_id == for_job.id } || character_jobs.find_or_create_by!(job: for_job)
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
    (native_abilities + slotted_abilities).uniq.reject(&:field?)
  end

  # The current job's passive, and every mastered job's: mastery keeps it.
  def passives
    mastered = character_jobs.includes(:job).select(&:mastered?).map { |cj| cj.job.passive }
    ([ job.passive ] + mastered).compact.uniq
  end

  # --- mastery -------------------------------------------------------------

  # Each learned ability's mastery, the best any job has given it (ties go
  # to the current job): { ability => { percent:, job: } }.
  def masteries
    @masteries ||= character_jobs.includes(job: { job_levels: :ability }).flat_map do |cj|
      cj.learned_levels.map { |row| { ability: row.ability, percent: cj.mastery(row), job: cj.job } }
    end.group_by { |m| m[:ability] }.transform_values do |list|
      list.max_by { |m| [ m[:percent], m[:job] == job ? 1 : 0 ] }
    end
  end

  # Does the current job teach it? Then it's used in its own job, and gets
  # the active-job bonus (Stats::Mastery::ACTIVE_BONUS).
  def active?(ability)
    job.job_levels.any? { |row| row.ability_id == ability.id }
  end

  # What mastery and the active job make of each move the character brings
  # to battle (Battle::State.job_parts). The job's own command grows with
  # the job level, as if learned at level 1. A mastered move used outside
  # its job keeps that job's str and mag where they're higher.
  def battle_mastery
    entries = battle_abilities.filter_map do |ability|
      mastery = masteries[ability] or next
      active = active?(ability)
      entry = { "power" => Stats::Mastery.power(mastery[:percent], active: active) }
      if mastery[:percent] == Stats::Mastery::FULL && !active && mastery[:job] != job
        basis = home_stats(mastery[:job]).select { |stat, value| value > stats[stat] }
        entry["stats"] = basis if basis.any?
      end
      [ ability.slug, entry ]
    end.to_h
    if job.signature
      percent = Stats::Mastery.percent(character_job.level, 1).to_i
      entries[job.signature] = { "power" => Stats::Mastery.power(percent, active: true) }
    end
    entries.reject { |_, entry| entry == { "power" => 100 } }
  end

  # A job's stats for this character, in their gear: what a mastered move
  # from that job brings to another.
  def home_stats(home)
    base = Stats::Growth.base_stats(level)
    Stats::Derivation.derive(base: base, job: home.to_derivation, equipment: equipped_items.map(&:to_equipment), passives: home.passives)
                     .slice("str", "mag")
  end

  # Switch job. Gear the new job can't use goes back to the bag; ability
  # slots beyond the new job's count are cleared.
  def change_job!(new_job)
    unless new_job.world_id == world.id
      errors.add(:job, "must come from #{world.name}")
      raise ActiveRecord::RecordInvalid, self
    end
    unless campaign.job_open?(new_job)
      errors.add(:job, "#{new_job.name} isn't open in #{campaign.name} yet")
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

  private

  def job_open_in_the_campaign
    errors.add(:job, "#{job.name} isn't open in #{campaign.name} yet") if job && campaign && !campaign.job_open?(job)
  end

  def job_from_the_campaign_world
    errors.add(:job, "must come from #{world.name}") if job && campaign && job.world_id != campaign.world_id
  end
end
