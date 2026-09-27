# frozen_string_literal: true

# Location turns: a place's prepared other state (the city burns, the mine
# floods), which the GM sets off and puts back. The world doesn't change;
# the place does.
class AddTurnsToLocations < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :turns, :json, null: false, default: []
    add_column :locations, :turn, :string
    add_column :scenes, :turn_key, :string
  end
end
