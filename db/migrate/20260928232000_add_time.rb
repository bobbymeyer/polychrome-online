# frozen_string_literal: true

# Time passing (Campaign#pass_time!): the day, and the part of it. Roads take
# a number of parts of the day; a world can name its days and months.
class AddTime < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :day, :integer, null: false, default: 1
    add_column :campaigns, :time_of_day, :string, null: false, default: "dawn"
    add_column :map_edges, :duration, :integer, null: false, default: 1
    add_column :world_routes, :duration, :integer, null: false, default: 1
    add_column :worlds, :calendar, :json, null: false, default: {}
  end
end
