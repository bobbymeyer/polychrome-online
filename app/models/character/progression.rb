# frozen_string_literal: true

# Levels from EXP and job levels from ABP: where a new character starts,
# and what a battle's rewards change.
module Character::Progression
  extend ActiveSupport::Concern

  class_methods do
    # Without a job level given, a character has spent some of their life in
    # their job: about two job levels per character level.
    def job_level_for(level)
      (level.to_i * 2).clamp(1, Stats::Growth::MAX_JOB_LEVEL)
    end
  end

  def exp_to_next
    Stats::Growth.exp_for_level(level + 1) - exp unless level >= Stats::Growth::MAX_LEVEL
  end

  # Award EXP and ABP (to the current job). Returns what changed, for the
  # battle's settlement summary.
  def gain!(exp: 0, abp: 0)
    cj = character_job
    before_level = level
    before_learned = cj.learned_abilities
    before_mastered = cj.mastered_abilities
    before_job_level = cj.level
    was_mastered = cj.mastered?
    transaction do
      cj.update!(abp: cj.abp + abp)
      update!(exp: self.exp + exp)
    end
    @masteries = nil
    learned = cj.learned_abilities - before_learned
    mastered = cj.mastered_abilities - before_mastered
    {
      "exp" => exp, "abp" => abp,
      "level" => (level > before_level ? [ before_level, level ] : nil),
      "job_level" => (cj.level > before_job_level ? [ before_job_level, cj.level ] : nil),
      "learned" => learned.map(&:name),
      # For the result panel's cards: what each new ability does, and what's
      # been mastered.
      "abilities" => learned.map { |a| { "name" => a.name, "description" => a.description.to_s } }.presence,
      "mastered_abilities" => mastered.map(&:name).presence,
      "mastered" => (cj.mastered? && !was_mastered ? { "job" => job.name, "passive" => job.passive } : nil),
      "to_next" => (Stats::Growth.exp_for_level(level + 1) - self.exp if level < Stats::Growth::MAX_LEVEL),
      "next_lesson" => cj.next_lesson&.then { |n| { "name" => n[:ability].name, "job_level" => n[:level], "abp" => n[:abp] } }
    }.compact
  end

  private

  def apply_starting_level
    self.exp = Stats::Growth.exp_for_level(starting_level) if starting_level
  end

  def start_in_job
    job_level = starting_job_level.nil? ? Character.job_level_for(level) : starting_job_level.to_i
    character_jobs.create!(job: job, abp: Stats::Growth.abp_for_job_level(job_level))
  end
end
