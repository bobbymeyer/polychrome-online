# frozen_string_literal: true

# How a thing is drawn, in one place (Art): the subject's art notes, LoRAs
# and model, and the seed, prompt and recipe that made its picture. These
# were the same columns on eleven tables. Generator tables had them too,
# unused: they're raw material, with no art of their own.
class CreateArts < ActiveRecord::Migration[8.1]
  SUBJECTS = {
    "abilities" => "Ability", "encounter_tables" => "EncounterTable", "items" => "Item", "jobs" => "Job",
    "location_templates" => "LocationTemplate", "monsters" => "Monster", "characters" => "Character", "npcs" => "Npc",
    "world_figures" => "WorldFigure", "mode_arts" => "ModeArt", "portraits" => "Portrait"
  }.freeze
  COLUMNS = { "notes" => "art_notes", "loras" => "art_loras", "model" => "art_model",
              "seed" => "image_seed", "prompt" => "image_prompt", "recipe" => "image_recipe" }.freeze

  def up
    create_table :arts do |t|
      t.references :subject, polymorphic: true, null: false, index: { unique: true }
      t.text :notes
      t.json :loras, default: [], null: false
      t.string :model
      t.integer :seed
      t.text :prompt
      t.json :recipe
      t.timestamps
    end

    SUBJECTS.each do |table, type|
      have = COLUMNS.select { |_, old| column_exists?(table, old) }
      picks = COLUMNS.map { |_, old| have.value?(old) ? old : "NULL" }
      picks[1] = "COALESCE(art_loras, '[]')" if have.key?("loras")
      picks[1] = "'[]'" unless have.key?("loras")
      something = have.map do |new, old|
        case new
        when "loras" then "COALESCE(#{old}, '[]') NOT IN ('[]', '')"
        when "seed", "recipe" then "#{old} IS NOT NULL"
        else "COALESCE(#{old}, '') != ''"
        end
      end
      execute <<~SQL
        INSERT INTO arts (subject_type, subject_id, #{COLUMNS.keys.join(', ')}, created_at, updated_at)
        SELECT '#{type}', id, #{picks.join(', ')}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP FROM #{table}
        WHERE #{something.join(' OR ')}
      SQL
      have.each_value { |old| remove_column table, old }
    end
    COLUMNS.each_value { |old| remove_column :generator_tables, old if column_exists?(:generator_tables, old) }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
