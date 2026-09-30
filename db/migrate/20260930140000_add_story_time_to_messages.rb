# frozen_string_literal: true

# When a line was said in the story (the campaign's day and part of it), so
# the log and the recap tell story time, not the clock on the wall.
class AddStoryTimeToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :day, :integer
    add_column :messages, :time_of_day, :string
  end
end
