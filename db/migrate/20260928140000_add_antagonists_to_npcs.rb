# frozen_string_literal: true

# Recurring antagonists: an NPC who fights as a Bestiary entry, under their
# own name and face, and who can get away and come back stronger.
class AddAntagonistsToNpcs < ActiveRecord::Migration[8.1]
  def change
    add_reference :npcs, :monster, foreign_key: true
    add_column :npcs, :escapes, :integer, null: false, default: 0
    add_column :npcs, :defeated_at, :datetime
  end
end
