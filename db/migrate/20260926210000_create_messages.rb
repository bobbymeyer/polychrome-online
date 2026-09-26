# frozen_string_literal: true

# Chat with portraits and GM possession (docs/HANDOFF.md §4, §7).
class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    # People the GM can speak as. Authored by hand for now; the town
    # generator (build step 7) will create them too.
    create_table :npcs do |t|
      t.references :campaign, null: false, foreign_key: true
      t.string :name, null: false
      t.string :title
      t.text :description
      t.timestamps
    end

    # One image per expression, for NPCs and characters alike.
    create_table :portraits do |t|
      t.references :owner, polymorphic: true, null: false
      t.string :expression, null: false
      t.timestamps
      t.index %i[owner_type owner_id expression], unique: true
    end

    create_table :messages do |t|
      t.references :campaign, null: false, foreign_key: true
      # Character or Npc; nil when the GM speaks as narrator.
      t.references :speaker, polymorphic: true
      # For whispers: the character whispered to; nil means to the GM.
      t.references :recipient, foreign_key: { to_table: :characters }
      # System lines point at the battle they announce.
      t.references :battle, foreign_key: true
      t.string :kind, null: false, default: "say"
      t.string :scope, null: false, default: "table"
      t.string :expression
      t.text :body, null: false
      t.timestamps
      t.index %i[campaign_id created_at]
    end
  end
end
