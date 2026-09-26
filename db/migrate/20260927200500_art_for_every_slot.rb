# Every image slot can be uploaded or generated (docs/HANDOFF.md §8): the two
# remaining books, and speaker portraits. A speaker (NPC or character) is the
# portrait's subject layer, with its own specifics and LoRAs; each portrait
# keeps the recipe of its generated image.
class ArtForEverySlot < ActiveRecord::Migration[8.1]
  def change
    %i[encounter_tables generator_tables npcs characters].each do |table|
      add_column table, :art_notes, :text
      add_column table, :art_loras, :json, null: false, default: []
    end
    add_column :encounter_tables, :image_recipe, :json
    add_column :generator_tables, :image_recipe, :json

    add_column :portraits, :image_seed, :integer
    add_column :portraits, :image_prompt, :text
    add_column :portraits, :image_recipe, :json
  end
end
