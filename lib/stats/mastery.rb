# frozen_string_literal: true

module Stats
  # Pure mastery math. Integer-only, no I/O.
  #
  # An ability is learned at a job level (the job's learn table) and
  # mastered SPAN job levels later, or at the top job level if that comes
  # first, so every ability of a job is mastered at MAX_JOB_LEVEL: job
  # mastery. On the way, its power grows from 100% to 100 + MASTERY_BONUS.
  #
  # Used while in the job it belongs to, an ability gets ACTIVE_BONUS on
  # top. The numbers are picked so a master who has moved on still beats a
  # beginner in the job: 150% against 125%.
  module Mastery
    SPAN = 40
    MASTERY_BONUS = 50
    ACTIVE_BONUS = 25
    FULL = 100

    module_function

    def mastered_at(learned_at)
      [ learned_at + SPAN, Growth::MAX_JOB_LEVEL ].min
    end

    # How far along an ability is, 0 to FULL percent; nil if not learned.
    def percent(job_level, learned_at)
      return if job_level < learned_at

      top = mastered_at(learned_at)
      return FULL if job_level >= top

      (job_level - learned_at) * FULL / (top - learned_at)
    end

    def mastered?(job_level, learned_at)
      percent(job_level, learned_at) == FULL
    end

    # The ability's power, as a percent of its written power.
    def power(percent, active:)
      100 + (percent.to_i * MASTERY_BONUS / FULL) + (active ? ACTIVE_BONUS : 0)
    end
  end
end
