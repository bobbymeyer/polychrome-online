# frozen_string_literal: true

# One row of a job's learn table: `ability` comes at job level `level`, and
# is mastered some levels later (Stats::Mastery).
class JobLevel < ApplicationRecord
  belongs_to :job, inverse_of: :job_levels
  belongs_to :ability

  validates :level, numericality: { only_integer: true, in: 1..Stats::Growth::MAX_JOB_LEVEL }
  validates :ability_id, uniqueness: { scope: :job_id, message: "is already in the learn table" }
  validate :ability_from_the_same_world

  def mastered_at
    Stats::Mastery.mastered_at(level)
  end

  private

  def ability_from_the_same_world
    return unless job && ability

    errors.add(:ability, "must come from the #{job.world.name} Grimoire") unless ability.world_id == job.world_id
  end
end
