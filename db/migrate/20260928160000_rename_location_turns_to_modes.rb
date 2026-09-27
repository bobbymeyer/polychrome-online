# frozen_string_literal: true

# "Turn" is kept free for what it may mean later (a dungeon turn, a turn of
# time). A place's prepared other state is its mode.
class RenameLocationTurnsToModes < ActiveRecord::Migration[8.1]
  def change
    rename_column :locations, :turns, :modes
    rename_column :locations, :turn, :mode
    rename_column :scenes, :turn_key, :mode_key
    reversible do |dir|
      dir.up { execute "UPDATE scenes SET ending = 'mode' WHERE ending = 'turn'" }
      dir.down { execute "UPDATE scenes SET ending = 'turn' WHERE ending = 'mode'" }
    end
  end
end
