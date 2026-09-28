# frozen_string_literal: true

# The world moving overnight (Pointcrawl::Overnight): rumours that travel
# a road a day, and each town's prices, pushed up when a caravan is lost.
class CreateRumours < ActiveRecord::Migration[8.1]
  def change
    create_table :rumours do |t|
      t.references :campaign, null: false, foreign_key: true
      t.text :body, null: false
      t.references :origin, foreign_key: { to_table: :map_nodes, on_delete: :nullify }
      t.json :reached, default: [], null: false
      t.integer :age, default: 0, null: false
      t.boolean :heard, default: false, null: false
      t.boolean :faded, default: false, null: false
      t.timestamps
    end
    add_column :locations, :prices, :integer, default: 0, null: false
  end
end
