# frozen_string_literal: true

# What Oda's archetypes need from the books and the table (docs/ODA.md):
# moves that reload and reach, giants and duellists in the Bestiary, each
# archetype's duel technique, masks in the Armory, cowards, a challenge
# waiting for its answer, and duels among the battles.
class OdaArchetypes < ActiveRecord::Migration[8.0]
  def change
    add_column :abilities, :reload_turns, :integer, default: 0, null: false
    add_column :abilities, :reach, :boolean, default: false, null: false
    add_column :monsters, :giant, :boolean, default: false, null: false
    add_column :monsters, :tells, :json, default: {}, null: false
    add_column :monsters, :technique, :string
    add_column :jobs, :technique, :string
    add_column :items, :mask, :json, default: {}, null: false
    add_column :characters, :coward, :boolean, default: false, null: false
    add_column :campaigns, :challenge, :json
    add_column :battles, :kind, :string, default: "battle", null: false
  end
end
