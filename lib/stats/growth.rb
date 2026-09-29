# frozen_string_literal: true

module Stats
  # Pure progression math: character level from EXP, base stats from level,
  # and job level from ABP. Integer-only, no I/O (docs/HANDOFF.md §12).
  #
  # Job levels run from 0 (nothing yet) to MAX_JOB_LEVEL on one curve for
  # every job: quick at first, slow at the top. A job's learn table says at
  # which job level each ability comes; the long climb after the last one
  # is mastery (Stats::Mastery). At about 8 ABP a battle, the last ability
  # of a base-world job (at job level 50) comes after some 25 battles, one
  # every few fights on the way, and job level 100 after some 90.
  module Growth
    MAX_LEVEL = 99
    MAX_JOB_LEVEL = 100

    module_function

    # Total EXP needed to reach `level` (level 1 needs none).
    def exp_for_level(level)
      level = level.clamp(1, MAX_LEVEL)
      10 * (level - 1) * level
    end

    def level_for_exp(exp)
      level = 1
      level += 1 while level < MAX_LEVEL && exp_for_level(level + 1) <= exp
      level
    end

    # Base stats at a level, before job, equipment and passives. Level 5 is
    # roughly a fresh adventurer: 150 HP, 30 MP, 12 in each core stat. From
    # there each level is a point in every core stat, so a level up is felt.
    def base_stats(level)
      level = level.clamp(1, MAX_LEVEL)
      core = [ 9 + (level * 3 / 5), 7 + level ].max
      {
        "max_hp" => 80 + 14 * level, "max_mp" => 15 + 3 * level,
        "str" => core, "mag" => core, "vit" => core, "spr" => core, "agi" => core,
        "atk" => 0, "def" => 0, "mdef" => 0
      }
    end

    # Total ABP at which a job reaches `level`: level + level²/16, so level
    # 10 at 16 ABP, 60 at 285 and 100 at 725.
    def abp_for_job_level(level)
      level = level.clamp(0, MAX_JOB_LEVEL)
      level + (level * level / 16)
    end

    def job_level(abp)
      level = 0
      level += 1 while level < MAX_JOB_LEVEL && abp_for_job_level(level + 1) <= abp
      level
    end
  end
end
