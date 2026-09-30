# frozen_string_literal: true

# A mode can come on by itself at parts of the day (a place by night), and
# an atlas place can say what it's like by night.
class AddHoursToModes < ActiveRecord::Migration[8.1]
  def change
    add_column :location_modes, :times, :json, default: [], null: false
    add_column :world_places, :night_line, :text
  end
end
