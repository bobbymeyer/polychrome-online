# frozen_string_literal: true

# A place's modes layer: the one the table set off, and any the calendar
# brings on by itself (a place by night, in winter), each able to add
# things to do. A place's current mode is only ever the table's now; the
# calendar's are worked out from the date.
class LayerTheModes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :location_modes, :activities, :text
    execute <<~SQL
      UPDATE locations SET current_mode_id = NULL
      WHERE current_mode_id IN (SELECT id FROM location_modes WHERE json_array_length(times) > 0)
    SQL
  end

  def down
    remove_column :location_modes, :activities
  end
end
