# frozen_string_literal: true

# What the history wrote into the canon is the GM's once they change it.
# That was guessed from updated_at > created_at, which anything touching a
# row would trip. Now it's said: `edited`, set when a GM saves one.
class AddEditedToCanon < ActiveRecord::Migration[8.1]
  # Rolling back rebuilds world_figures, whose front secrets would lose
  # their person to an ON DELETE action inside a transaction.
  disable_ddl_transaction!

  TABLES = %i[codex_entries world_figures world_fronts].freeze

  def up
    TABLES.each do |table|
      add_column table, :edited, :boolean, default: false, null: false
      execute "UPDATE #{table} SET edited = 1 WHERE history_key IS NOT NULL AND updated_at > created_at"
    end
  end

  def down
    TABLES.each { |table| remove_column table, :edited }
  end
end
