# frozen_string_literal: true

# A character's progress in one job: ABP earned and the job level it buys
# (Stats::Growth.job_level, one curve to 100 for every job). Level is
# stored for the sheet and kept in step with ABP on every save.
#
# Each ability in the job's learn table comes at its job level and grows
# towards mastery from there (Stats::Mastery). Job level 100 masters them
# all: the job is mastered.
class CharacterJob < ApplicationRecord
  belongs_to :character
  belongs_to :job

  validates :abp, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :job_id, uniqueness: { scope: :character_id }

  before_save { self.level = Stats::Growth.job_level(abp) }

  def mastered?
    level >= Stats::Growth::MAX_JOB_LEVEL
  end

  # ABP still needed for the next job level, or nil when mastered.
  def abp_to_next
    Stats::Growth.abp_for_job_level(level + 1) - abp unless mastered?
  end

  def learned_levels
    job.job_levels.select { |row| row.level <= level }
  end

  def learned_abilities
    learned_levels.map(&:ability)
  end

  # The next thing the job teaches, and how far off it is:
  # { ability:, level:, abp: } (ABP still to earn), or nil once all are learned.
  def next_lesson
    row = job.job_levels.find { |r| r.level > level } or return
    { ability: row.ability, level: row.level, abp: Stats::Growth.abp_for_job_level(row.level) - abp }
  end

  # How far along each learned ability is here, 0 to 100 percent.
  def mastery(row)
    Stats::Mastery.percent(level, row.level)
  end

  def mastered_abilities
    learned_levels.select { |row| mastery(row) == Stats::Mastery::FULL }.map(&:ability)
  end
end
