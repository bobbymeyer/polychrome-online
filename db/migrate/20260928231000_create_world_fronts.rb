# frozen_string_literal: true

# A setting's pressures, written once (WorldFront): the Syndicate's plan,
# as clocks and secrets, dealt into any campaign that wants it.
class CreateWorldFronts < ActiveRecord::Migration[8.1]
  def change
    create_table :world_fronts do |t|
      t.references :world, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.json :clocks, null: false, default: []
      t.json :secrets, null: false, default: []
      t.timestamps
    end
    add_reference :clocks, :world_front, foreign_key: true
    add_reference :secrets, :world_front, foreign_key: true
  end
end
