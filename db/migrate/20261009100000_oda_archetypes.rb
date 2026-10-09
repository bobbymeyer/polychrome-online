# frozen_string_literal: true

# What Oda's archetypes need from the books and the table (docs/ODA.md):
# moves that reload and reach, giants in the Bestiary, masks in the
# Armory, cowards, a challenge waiting for its answer, and duels: a scene of
# their own at the table, outside battle (Duel).
class OdaArchetypes < ActiveRecord::Migration[8.0]
  def change
    add_column :abilities, :reload_turns, :integer, default: 0, null: false
    add_column :abilities, :reach, :boolean, default: false, null: false
    add_column :monsters, :giant, :boolean, default: false, null: false
    add_column :items, :mask, :json, default: {}, null: false
    add_column :characters, :coward, :boolean, default: false, null: false
    add_column :campaigns, :challenge, :json

    # A duel: a character against someone the GM plays, three swings each
    # on a meter (DuelMeter). rounds: [{ "zone" => {...}, "swings" => { "character" => {...}, "gm" => {...} } }].
    create_table :duels do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :character, null: false, foreign_key: true
      t.references :npc, foreign_key: true
      t.string :opponent_name, null: false
      t.integer :seed, null: false
      t.json :rounds, default: [], null: false
      t.string :status, default: "on", null: false
      t.string :result
      t.timestamps
    end
  end
end
