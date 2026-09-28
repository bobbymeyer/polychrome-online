# frozen_string_literal: true

# Where a rumour has got to was a JSON array of map node ids: foreign keys
# without the integrity, and invisible to SQL. It's rows now (RumourPlace).
# A town's view of the party is no longer stored: it's the sway of the deed
# rumours that have reached it (Location::Town#reputation). And a rumour
# remembers where the party heard it.
class CreateRumourPlaces < ActiveRecord::Migration[8.1]
  # Removing a column rebuilds the table in SQLite, and inside a transaction
  # SQLite can't switch foreign keys off: the rebuild would fire ON DELETE
  # actions elsewhere (a character's choice picks cascade away). Outside
  # one, Rails switches them off for the rebuild.
  disable_ddl_transaction!

  class Rumour < ActiveRecord::Base
    self.table_name = "rumours"
  end

  def up
    create_table :rumour_places do |t|
      # Plain foreign keys: the models clean up (Rumour, MapNode). An ON DELETE
      # action here would fire whenever a later migration rebuilt its parent.
      t.references :rumour, null: false, foreign_key: true
      t.references :map_node, null: false, foreign_key: true
      t.integer :day
      t.timestamps
      t.index %i[rumour_id map_node_id], unique: true
    end
    add_reference :rumours, :heard_at, foreign_key: { to_table: :map_nodes }

    Rumour.find_each do |rumour|
      Array(rumour.reached).uniq.each do |node_id|
        next unless select_value("SELECT id FROM map_nodes WHERE id = #{node_id.to_i}")

        execute "INSERT INTO rumour_places (rumour_id, map_node_id, created_at, updated_at) " \
                "VALUES (#{rumour.id}, #{node_id.to_i}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
      end
    end

    remove_column :rumours, :reached
    remove_column :locations, :reputation
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
