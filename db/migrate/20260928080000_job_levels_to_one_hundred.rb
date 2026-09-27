# frozen_string_literal: true

# Job levels on one curve from 0 to 100 for every job (Stats::Growth), with
# each learn-table row saying the job level its ability comes at, and a
# type for every job.
#
# A row used to cost ABP on top of the rows before it. It now comes at the
# highest job level that total ABP buys on the new curve, so nobody learns
# anything later than they did. Characters keep their ABP; their job level
# is read off the new curve.
class JobLevelsToOneHundred < ActiveRecord::Migration[8.1]
  # The curve, frozen here as it was when this ran (Stats::Growth).
  def self.abp_for(level) = level + (level * level / 16)

  def self.level_for(abp)
    level = 0
    level += 1 while level < 100 && abp_for(level + 1) <= abp
    level
  end

  BASE_TYPES = { "knight" => "steel", "thief" => "dark", "monk" => "fighting", "black_mage" => "fire",
                 "white_mage" => "psychic", "summoner" => "ghost", "geomancer" => "ground", "dragoon" => "flying" }.freeze

  def up
    add_column :jobs, :base_type, :string, null: false, default: "normal"
    remove_index :job_levels, %i[job_id level]

    select_rows("SELECT id, slug FROM jobs").each do |id, slug|
      type = BASE_TYPES[slug]
      execute("UPDATE jobs SET base_type = #{quote(type)} WHERE id = #{id}") if type

      total = 0
      select_rows("SELECT id, abp FROM job_levels WHERE job_id = #{id} ORDER BY level").each do |row_id, abp|
        total += abp
        execute("UPDATE job_levels SET level = #{self.class.level_for(total).clamp(1, 100)} WHERE id = #{row_id}")
      end
    end

    select_rows("SELECT id, abp FROM character_jobs").each do |id, abp|
      execute("UPDATE character_jobs SET level = #{self.class.level_for(abp)} WHERE id = #{id}")
    end

    remove_column :job_levels, :abp
    add_index :job_levels, %i[job_id ability_id], unique: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
