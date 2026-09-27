# frozen_string_literal: true

# What a line needs beyond its words: a check's chance and roll, for the
# moment everyone watches it land.
class AddDataToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :data, :json, null: false, default: {}
  end
end
