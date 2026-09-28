# frozen_string_literal: true

# Where characters come from (World#origins, Character#origin), their home on
# the map, and who they're tied to in the cast.
class AddOrigins < ActiveRecord::Migration[8.1]
  def change
    add_column :worlds, :origins, :json, null: false, default: []
    add_column :characters, :origin, :string
    add_reference :characters, :home_node, foreign_key: { to_table: :map_nodes }
    add_column :characters, :ties, :json, null: false, default: []
  end
end
