# frozen_string_literal: true

module Stats
  # Pure progression math: character level from EXP, base stats from level,
  # and job level from ABP. Integer-only, no I/O (docs/HANDOFF.md §12).
  #
  # Job levels follow the learn table (§4 `job_levels`): each row's ABP is
  # the cost of reaching that level from the one before, so a job is at
  # level N once its total ABP covers the first N rows. Level 0 means
  # nothing learned yet.
  module Growth
    MAX_LEVEL = 99

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
    # roughly a fresh adventurer: 150 HP, 30 MP, 12 in each core stat.
    def base_stats(level)
      level = level.clamp(1, MAX_LEVEL)
      core = 9 + (level * 3 / 5)
      {
        "max_hp" => 80 + 14 * level, "max_mp" => 15 + 3 * level,
        "str" => core, "mag" => core, "vit" => core, "spr" => core, "agi" => core,
        "atk" => 0, "def" => 0, "mdef" => 0
      }
    end

    # costs: ABP per learn-table row, in level order.
    def job_level(abp, costs)
      total = 0
      costs.take_while { |cost| (total += cost) <= abp }.size
    end

    # Total ABP at which a job reaches `level`.
    def abp_for_job_level(level, costs)
      costs.first(level.clamp(0, costs.size)).sum
    end
  end
end
