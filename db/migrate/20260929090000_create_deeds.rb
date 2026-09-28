# frozen_string_literal: true

# What the party does becomes part of the world: deeds, told as rumours
# that carry the party's name, and a town's view of them (reputation) that
# moves as the news arrives. Secrets can leak out as rumours too.
class CreateDeeds < ActiveRecord::Migration[8.1]
  def change
    create_table :deeds do |t|
      t.references :campaign, null: false, foreign_key: true
      t.text :body, null: false
      t.references :map_node, foreign_key: { on_delete: :nullify }
      t.integer :day, null: false
      t.integer :sway, default: 0, null: false
      t.string :kind, default: "gm", null: false
      t.timestamps
    end
    add_column :rumours, :sway, :integer, default: 0, null: false
    add_reference :rumours, :deed, foreign_key: { on_delete: :nullify }
    add_reference :rumours, :secret, foreign_key: { on_delete: :nullify }
    add_column :rumours, :heard_day, :integer
    add_column :locations, :reputation, :integer, default: 0, null: false
  end
end
