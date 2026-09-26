# frozen_string_literal: true

# The session layer's battle tables (docs/HANDOFF.md §4). `initial_state`
# plus the ordered `battle_actions` reproduce `state` exactly through
# Battle::Replay; `battle_events` is the resolver's output log.
class CreateBattles < ActiveRecord::Migration[8.1]
  def change
    create_table :battles do |t|
      t.references :world, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :seed, null: false
      t.string :status, null: false, default: "input"
      t.integer :round, null: false, default: 1
      t.json :initial_state, null: false
      t.json :state, null: false
      # Input timer (§5, §9.3): seconds per round, nil for no timer.
      t.integer :input_seconds
      t.datetime :deadline_at
      # GM fast-forward (§6): the playback speed every viewer uses.
      t.integer :playback_speed, null: false, default: 1
      t.timestamps
    end

    create_table :battle_actions do |t|
      t.references :battle, null: false, foreign_key: true
      t.integer :position, null: false
      # A party unit id, "gm", or "system" (the input timer).
      t.string :actor, null: false
      t.json :payload, null: false
      t.timestamps
      t.index %i[battle_id position], unique: true
    end

    create_table :battle_events do |t|
      t.references :battle, null: false, foreign_key: true
      t.references :battle_action, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :kind, null: false
      t.json :payload, null: false
      t.timestamps
      t.index %i[battle_id position], unique: true
    end
  end
end
