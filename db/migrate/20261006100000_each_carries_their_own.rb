# frozen_string_literal: true

# Items and equipment are each character's own: an inventory row belongs to
# a character, or to nobody, which is the party's chest. What the party had
# in its bag is in the chest now.
class EachCarriesTheirOwn < ActiveRecord::Migration[8.1]
  def change
    add_reference :inventories, :character, null: true, foreign_key: true
    remove_index :inventories, column: %i[campaign_id item_id], unique: true
    add_index :inventories, %i[campaign_id character_id item_id], unique: true
  end
end
