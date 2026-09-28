# frozen_string_literal: true

# The GM's pressure and prep: clocks that fill as the party dawdles, and
# secrets the party can find out.
class CreateClocksAndSecrets < ActiveRecord::Migration[8.1]
  def change
    create_table :clocks do |t|
      t.references :campaign, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :segments, null: false, default: 6
      t.integer :filled, null: false, default: 0
      t.boolean :public, null: false, default: false
      t.json :triggers, null: false, default: []
      t.text :full_line
      t.references :location, foreign_key: true
      t.string :mode_key
      t.datetime :full_at
      t.timestamps
    end

    create_table :secrets do |t|
      t.references :campaign, null: false, foreign_key: true
      t.text :body, null: false
      t.references :location, foreign_key: true
      t.references :npc, foreign_key: true
      t.datetime :revealed_at
      t.string :revealed_by
      t.timestamps
    end
  end
end
