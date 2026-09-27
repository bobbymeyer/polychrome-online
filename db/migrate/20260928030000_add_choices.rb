# frozen_string_literal: true

# Choices for the table: a line of kind "choice" with its options, the
# flag its outcome sets, and the option the GM settled on. Each character
# picks one.
class AddChoices < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :options, :json, null: false, default: []
    add_column :messages, :flag_key, :string
    add_column :messages, :settled, :string

    create_table :choice_picks do |t|
      t.references :message, null: false, foreign_key: { on_delete: :cascade }
      t.references :character, null: false, foreign_key: { on_delete: :cascade }
      t.string :option, null: false
      t.timestamps
    end
    add_index :choice_picks, %i[message_id character_id], unique: true
  end
end
