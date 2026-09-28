# frozen_string_literal: true

# A location mode's own picture (§8): the place, drawn as it is in that
# mode, so the burning city looks it.
class CreateModeArts < ActiveRecord::Migration[8.1]
  def change
    create_table :mode_arts do |t|
      t.references :location, null: false, foreign_key: true
      t.string :mode_key, null: false
      t.integer :image_seed
      t.text :image_prompt
      t.json :image_recipe
      t.timestamps
      t.index %i[location_id mode_key], unique: true
    end
  end
end
