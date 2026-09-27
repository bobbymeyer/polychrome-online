# frozen_string_literal: true

# Field abilities: a job's move outside battle (Pick Lock, Forage, Scout),
# a skill check the player asks for and the GM approves or vetoes, with an
# outcome the game applies. Once per rest.
class AddFieldAbilities < ActiveRecord::Migration[8.1]
  def change
    add_column :abilities, :field_skill, :string
    add_column :abilities, :field_outcome, :string
    add_column :abilities, :field_difficulty, :string, null: false, default: "normal"
    add_column :abilities, :field_power, :integer, null: false, default: 0
    add_column :jobs, :field_ability, :string
    add_column :characters, :field_used, :boolean, null: false, default: false
    add_column :campaigns, :safe_road, :boolean, null: false, default: false

    create_table :field_uses do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :character, null: false, foreign_key: true
      t.references :ability, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :difficulty
      t.json :result, null: false, default: {}
      t.timestamps
    end
  end
end
