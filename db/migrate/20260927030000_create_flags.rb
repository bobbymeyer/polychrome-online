# frozen_string_literal: true

# Campaign flags (docs/HANDOFF.md §4): key/value state the GM keeps.
class CreateFlags < ActiveRecord::Migration[8.1]
  def change
    create_table :flags do |t|
      t.references :campaign, null: false, foreign_key: true
      t.string :key, null: false
      t.string :value, null: false, default: ""
      t.text :note
      # Public flags are shown to the players at the table ("what the party
      # knows"); the rest are the GM's alone.
      t.boolean :public, null: false, default: false
      t.timestamps
      t.index %i[campaign_id key], unique: true
    end
  end
end
