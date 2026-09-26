# frozen_string_literal: true

# A character's progress in one job: ABP earned and the job level it buys
# (Stats::Growth.job_level against the job's learn table). Level is stored
# for the sheet and kept in step with ABP on every save.
class CharacterJob < ApplicationRecord
  belongs_to :character
  belongs_to :job

  validates :abp, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :job_id, uniqueness: { scope: :character_id }

  before_save { self.level = Stats::Growth.job_level(abp, costs) }

  def costs
    job.job_levels.map(&:abp)
  end

  def mastered?
    level >= job.job_levels.size
  end

  # ABP still needed for the next job level, or nil when mastered.
  def abp_to_next
    Stats::Growth.abp_for_job_level(level + 1, costs) - abp unless mastered?
  end

  def learned_levels
    job.job_levels.first(level)
  end

  def learned_abilities
    learned_levels.map(&:ability)
  end
end
