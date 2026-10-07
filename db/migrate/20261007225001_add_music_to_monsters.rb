# frozen_string_literal: true

# A boss's own music: one of its world's tracks by name ("track:12"), played for the fight (Monster#music).
class AddMusicToMonsters < ActiveRecord::Migration[8.1]
  def change
    add_column :monsters, :music, :string
  end
end
