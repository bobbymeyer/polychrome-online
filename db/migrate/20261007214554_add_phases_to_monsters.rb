# frozen_string_literal: true

# A boss's phases: at an HP threshold it becomes another Bestiary entry, with a line (Monster#phases).
class AddPhasesToMonsters < ActiveRecord::Migration[8.1]
  def change
    add_column :monsters, :phases, :json, default: [], null: false
  end
end
