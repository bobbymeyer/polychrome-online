# frozen_string_literal: true

# A mode belongs to the place on the map, not only to a town or dungeon, so
# a landmark or the wilds can be different by night too (MapNode::Modes).
# The place holds the mode the table set it in. A landmark's night line
# becomes an ordinary "By night" mode, as a town's already is.
class ModesBelongToPlaces < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :location_modes, :map_node_id, :integer
    add_column :map_nodes, :current_mode_id, :integer
    execute <<~SQL
      UPDATE location_modes SET map_node_id = (SELECT map_nodes.id FROM map_nodes WHERE map_nodes.location_id = location_modes.location_id LIMIT 1)
    SQL
    execute <<~SQL
      UPDATE map_nodes SET current_mode_id = (SELECT locations.current_mode_id FROM locations WHERE locations.id = map_nodes.location_id)
      WHERE location_id IS NOT NULL
    SQL
    # A mode on a place no longer on the map has nowhere to be.
    execute "UPDATE clocks SET location_mode_id = NULL WHERE location_mode_id IN (SELECT id FROM location_modes WHERE map_node_id IS NULL)"
    execute "UPDATE scenes SET location_mode_id = NULL WHERE location_mode_id IN (SELECT id FROM location_modes WHERE map_node_id IS NULL)"
    execute "DELETE FROM mode_arts WHERE location_mode_id IN (SELECT id FROM location_modes WHERE map_node_id IS NULL)"
    execute "DELETE FROM location_modes WHERE map_node_id IS NULL"

    remove_foreign_key :locations, :location_modes, column: :current_mode_id
    remove_column :locations, :current_mode_id
    remove_foreign_key :location_modes, :locations
    remove_index :location_modes, %i[location_id key]
    remove_column :location_modes, :location_id
    change_column_null :location_modes, :map_node_id, false
    add_index :location_modes, %i[map_node_id key], unique: true
    add_index :map_nodes, :current_mode_id

    # Landmarks and the wilds with a night line in the atlas: a "By night" mode, in the setting's night.
    select_rows(<<~SQL).each do |node_id, line, calendar|
      SELECT map_nodes.id, world_places.night_line, worlds.calendar FROM map_nodes
      JOIN world_places ON world_places.id = map_nodes.world_place_id
      JOIN campaigns ON campaigns.id = map_nodes.campaign_id
      JOIN worlds ON worlds.id = campaigns.world_id
      WHERE map_nodes.location_id IS NULL AND world_places.night_line IS NOT NULL AND world_places.night_line != ''
    SQL
      settings = JSON.parse(calendar.presence || "{}")
      periods = Array(settings["periods"]).presence || %w[dawn day dusk night]
      dark = Array(settings["dark"]).presence || [ periods.size > 1 ? periods.last : "night" ]
      now = connection.quote(Time.current)
      execute <<~SQL
        INSERT INTO location_modes (map_node_id, key, name, line, closed, times, created_at, updated_at)
        VALUES (#{node_id.to_i}, 'by_night', 'By night', #{connection.quote(line)}, '[]', #{connection.quote(dark.to_json)}, #{now}, #{now})
      SQL
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
