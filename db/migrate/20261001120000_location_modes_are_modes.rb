# frozen_string_literal: true

# A mode belongs to a place on the map, not a location: it's a Mode, and
# what points at one says mode.
class LocationModesAreModes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    rename_table :location_modes, :modes
    rename_column :clocks, :location_mode_id, :mode_id
    rename_column :scenes, :location_mode_id, :mode_id
    rename_column :mode_arts, :location_mode_id, :mode_id
  end
end
