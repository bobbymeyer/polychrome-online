# frozen_string_literal: true

# A clock can come from a place ("the goblins raid Tule" from Goblin
# Hollow): clearing the place stops it.
class AddPlaceToClocks < ActiveRecord::Migration[8.1]
  def change
    add_column :clocks, :map_node_id, :integer
    add_index :clocks, :map_node_id
    add_column :clocks, :stopped_at, :datetime
  end
end
