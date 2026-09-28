# frozen_string_literal: true

# A location's modes were a JSON array, and clocks, scenes, mode pictures
# and the location itself pointed into it by key: foreign keys without the
# integrity. They're rows now (LocationMode), pointed at by id.
class CreateLocationModes < ActiveRecord::Migration[8.1]
  # Removing a column rebuilds the table in SQLite, and inside a transaction
  # SQLite can't switch foreign keys off: the rebuild would fire ON DELETE
  # actions elsewhere (a character's choice picks cascade away). Outside
  # one, Rails switches them off for the rebuild.
  disable_ddl_transaction!

  class Location < ActiveRecord::Base
    self.table_name = "locations"
  end

  class Mode < ActiveRecord::Base
    self.table_name = "location_modes"
  end

  def up
    create_table :location_modes do |t|
      t.references :location, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.text :line
      t.text :description
      t.json :closed, default: [], null: false
      t.string :music
      t.references :encounter_table, foreign_key: true
      t.text :art
      t.timestamps
      t.index %i[location_id key], unique: true
    end
    add_reference :locations, :current_mode, foreign_key: { to_table: :location_modes }
    add_reference :clocks, :location_mode, foreign_key: true
    add_reference :scenes, :location_mode, foreign_key: true
    add_reference :mode_arts, :location_mode, foreign_key: true

    move_modes
    point_at_modes

    execute "DELETE FROM mode_arts WHERE location_mode_id IS NULL"
    change_column_null :mode_arts, :location_mode_id, false
    remove_index :mode_arts, %i[location_id mode_key]
    remove_index :mode_arts, :location_mode_id
    add_index :mode_arts, :location_mode_id, unique: true
    remove_column :mode_arts, :mode_key
    remove_column :locations, :modes
    remove_column :locations, :mode
    remove_reference :clocks, :location, foreign_key: true, index: true
    remove_column :clocks, :mode_key
    remove_column :scenes, :mode_key
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def move_modes
    Location.find_each do |location|
      world_id = select_value("SELECT world_id FROM campaigns WHERE id = #{location.campaign_id.to_i}")
      Array(location.modes).each do |row|
        table = row["encounters"].presence &&
                select_value("SELECT id FROM encounter_tables WHERE world_id = #{world_id.to_i} AND slug = #{connection.quote(row['encounters'])}")
        mode = Mode.create!(location_id: location.id, key: row["key"], name: row["name"].presence || row["key"].to_s.humanize,
                            line: row["line"], description: row["description"], closed: Array(row["closed"]),
                            music: row["music"], encounter_table_id: table, art: row["art"])
        location.update_columns(current_mode_id: mode.id) if location.mode == row["key"]
      end
    end
  end

  def point_at_modes
    execute <<~SQL
      UPDATE clocks SET location_mode_id = (
        SELECT id FROM location_modes WHERE location_modes.location_id = clocks.location_id AND location_modes.key = clocks.mode_key)
      WHERE mode_key IS NOT NULL
    SQL
    execute <<~SQL
      UPDATE scenes SET location_mode_id = (
        SELECT location_modes.id FROM location_modes JOIN map_nodes ON map_nodes.location_id = location_modes.location_id
        WHERE map_nodes.id = scenes.map_node_id AND location_modes.key = scenes.mode_key)
      WHERE mode_key IS NOT NULL AND mode_key != ''
    SQL
    execute <<~SQL
      UPDATE mode_arts SET location_mode_id = (
        SELECT id FROM location_modes WHERE location_modes.location_id = mode_arts.location_id AND location_modes.key = mode_arts.mode_key)
    SQL
  end
end
