# frozen_string_literal: true

# A speaker's full-body figure for the stage (Sprite): one per NPC or
# character, uploaded or generated like their portraits, standing in a
# scene's beat where their portrait stood before.
class SpeakersHaveAFullBodySprite < ActiveRecord::Migration[8.1]
  def change
    create_table :sprites do |t|
      t.references :owner, polymorphic: true, null: false, index: { unique: true }
      t.timestamps
    end
  end
end
