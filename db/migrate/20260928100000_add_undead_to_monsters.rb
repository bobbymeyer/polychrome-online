# frozen_string_literal: true

# The undead (Battle::Effects): healing hurts them and drain runs backwards.
class AddUndeadToMonsters < ActiveRecord::Migration[8.1]
  def change
    add_column :monsters, :undead, :boolean, null: false, default: false
  end
end
