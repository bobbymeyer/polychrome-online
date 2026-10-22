# frozen_string_literal: true

# What a book entry was before each edit, so a world that is live (HANDOFF §9.8) can take an edit back: the entry's whole
# row as it stood, and the names of the columns the edit changed. Plain keys, no foreign keys: the models clean up.
class CreateBookRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :book_revisions do |t|
      t.integer :world_id, null: false
      t.string :record_type, null: false
      t.integer :record_id, null: false
      t.integer :user_id
      t.json :snapshot, null: false, default: {}
      t.json :changed_fields, null: false, default: []
      t.datetime :created_at, null: false
    end
    add_index :book_revisions, %i[record_type record_id id]
    add_index :book_revisions, %i[world_id id]
  end
end
