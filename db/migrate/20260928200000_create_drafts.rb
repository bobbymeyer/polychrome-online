# frozen_string_literal: true

# What the language model suggests for the GM to keep or throw away: secrets,
# clocks, a scene, a mode, an entry's description, a family's names, a
# setting's types and skills. Nothing it writes is used until it's kept.
class CreateDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :drafts do |t|
      t.references :owner, polymorphic: true, null: false
      t.string :kind, null: false
      t.string :target
      t.json :request, null: false, default: {}
      t.string :status, null: false, default: "queued"
      t.json :items, null: false, default: []
      t.text :error
      t.timestamps
      t.index %i[owner_type owner_id kind target]
    end
  end
end
