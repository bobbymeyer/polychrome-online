# frozen_string_literal: true

# A world's own battle rules (Battle::RULES), each off unless it says so.
class AddBattleRulesToWorlds < ActiveRecord::Migration[8.1]
  def change
    add_column :worlds, :battle_rules, :json, default: {}, null: false
  end
end
