# frozen_string_literal: true

# Sound: the GM's choice of music for the table (nil follows the scene), and
# a cue on a log line for the jingle it plays as it arrives.
class AddSound < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :music, :string
    add_column :messages, :cue, :string
  end
end
