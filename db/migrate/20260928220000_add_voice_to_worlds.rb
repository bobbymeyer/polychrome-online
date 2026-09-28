# frozen_string_literal: true

# How a setting sounds, and what it never does: its voice, touchstones and
# words to avoid (for the language model's drafts), and its lines and veils
# (for the table, and the model too).
class AddVoiceToWorlds < ActiveRecord::Migration[8.1]
  def change
    add_column :worlds, :voice, :text
    add_column :worlds, :avoid, :text
    add_column :worlds, :lines, :text
    add_column :worlds, :veils, :text
  end
end
