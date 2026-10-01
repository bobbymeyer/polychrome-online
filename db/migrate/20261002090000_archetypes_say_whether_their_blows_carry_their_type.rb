# frozen_string_literal: true

# Whether an archetype's Attack and signature strike as its type was read
# off its stats (more Mag than Str: a caster, plain blows), which took the
# Thief's dark blows away without anyone choosing that. The author says
# now (Job#typed_attack). Existing archetypes keep what the old rule gave
# them, so no world changes on deploy.
class ArchetypesSayWhetherTheirBlowsCarryTheirType < ActiveRecord::Migration[8.1]
  disable_ddl_transaction! # the way down removes a column (spec/migrations_spec.rb)

  def up
    add_column :jobs, :typed_attack, :boolean, default: true, null: false
    execute <<~SQL
      UPDATE jobs SET typed_attack = 0
      WHERE COALESCE(json_extract(stat_multipliers, '$.mag'), 100) > COALESCE(json_extract(stat_multipliers, '$.str'), 100)
    SQL
  end

  def down
    remove_column :jobs, :typed_attack
  end
end
