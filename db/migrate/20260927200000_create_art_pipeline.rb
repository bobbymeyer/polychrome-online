# The asset pipeline (docs/HANDOFF.md §8). A prompt is composed in layers:
# the world's house style, the content type's framing, then the entry's own
# specifics, each layer able to add LoRAs. A batch holds that composed recipe
# and its candidates; each candidate is its own ComfyUI job with its own seed,
# so the winner can be regenerated from what is stored on the entry.
class CreateArtPipeline < ActiveRecord::Migration[8.1]
  BOOKS = %i[monsters jobs items abilities location_templates].freeze

  def change
    # Layer 1: the world's house style.
    add_column :worlds, :art_style, :text
    add_column :worlds, :art_negative, :text
    add_column :worlds, :art_loras, :json, null: false, default: []
    add_column :worlds, :art_checkpoint, :string

    # Layer 2: framing per content type, per world.
    create_table :art_types do |t|
      t.references :world, null: false, foreign_key: true
      t.string :kind, null: false
      t.text :prompt
      t.text :negative
      t.json :loras, null: false, default: []
      t.integer :width, null: false, default: 1024
      t.integer :height, null: false, default: 1024
      t.boolean :transparent, null: false, default: true
      t.timestamps
      t.index %i[world_id kind], unique: true
    end

    # Layer 3: the entry's own specifics, and the full recipe of its image.
    BOOKS.each do |table|
      add_column table, :art_notes, :text
      add_column table, :art_loras, :json, null: false, default: []
      add_column table, :image_recipe, :json
    end

    create_table :art_batches do |t|
      t.references :world, null: false, foreign_key: true
      t.references :entry, polymorphic: true, null: false
      t.json :recipe, null: false, default: {}
      t.string :status, null: false, default: "queued"
      t.text :error
      t.timestamps
    end

    create_table :art_candidates do |t|
      t.references :art_batch, null: false, foreign_key: true
      t.integer :position, null: false
      t.integer :seed, null: false
      t.string :comfy_prompt_id
      t.string :status, null: false, default: "queued"
      t.text :error
      t.timestamps
    end
  end
end
