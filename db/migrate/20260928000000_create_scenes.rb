# frozen_string_literal: true

# A GM's prepared scene: lines written like a script, played into the table
# in order, and an ending (a battle, or a place revealed on the map).
class CreateScenes < ActiveRecord::Migration[8.1]
  def change
    create_table :scenes do |t|
      t.references :campaign, null: false, foreign_key: true
      t.string :name, null: false
      t.text :script
      t.string :ending, null: false, default: "none"
      t.json :encounter, null: false, default: {}
      t.references :map_node, foreign_key: { on_delete: :nullify }
      t.datetime :played_at
      t.timestamps
    end
  end
end
