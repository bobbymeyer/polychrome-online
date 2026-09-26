# frozen_string_literal: true

# One row of a job's learn table: reaching this job level costs `abp` and
# teaches `ability`.
class JobLevel < ApplicationRecord
  belongs_to :job, inverse_of: :job_levels
  belongs_to :ability

  validates :level, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :job_id }
  validates :abp, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :ability_from_the_same_world

  private

  def ability_from_the_same_world
    return unless job && ability

    errors.add(:ability, "must come from the #{job.world.name} Grimoire") unless ability.world_id == job.world_id
  end
end
