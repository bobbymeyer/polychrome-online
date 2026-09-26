# frozen_string_literal: true

# The setting layer's books (docs/HANDOFF.md §4). Every book table carries
# world_id. Structured parts of an entry that the engine reads verbatim
# (stat blocks, effect lists, AI scripts) are JSON in the engine's own
# shape; the models validate them against the engine's closed vocabularies.
class CreateBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :worlds do |t|
      t.string :name, null: false
      t.string :slug, null: false, index: { unique: true }
      t.text :description
      t.timestamps
    end

    create_table :abilities do |t|
      t.references :world, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :name, null: false
      t.string :kind, null: false, default: "skill"
      t.string :target, null: false
      t.integer :mp_cost, null: false, default: 0
      t.json :effects, null: false, default: []
      t.string :gesture
      t.text :description
      book_art(t)
      t.timestamps
      t.index %i[world_id slug], unique: true
    end

    create_table :items do |t|
      t.references :world, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :name, null: false
      t.string :category, null: false
      t.integer :price, null: false, default: 0
      t.json :stats, null: false, default: {}
      t.string :target
      t.json :effects, null: false, default: []
      t.text :description
      book_art(t)
      t.timestamps
      t.index %i[world_id slug], unique: true
    end

    create_table :jobs do |t|
      t.references :world, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :name, null: false
      t.json :stat_multipliers, null: false, default: {}
      t.json :equip_categories, null: false, default: []
      t.json :innates, null: false, default: []
      t.text :description
      book_art(t)
      t.timestamps
      t.index %i[world_id slug], unique: true
    end

    # The FF5 learn table: job level N costs this much ABP and teaches this
    # ability. (§4 calls it job_learn_tables; one row is one level.)
    create_table :job_levels do |t|
      t.references :job, null: false, foreign_key: true
      t.references :ability, null: false, foreign_key: true
      t.integer :level, null: false
      t.integer :abp, null: false
      t.timestamps
      t.index %i[job_id level], unique: true
    end

    create_table :monsters do |t|
      t.references :world, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :name, null: false
      t.integer :level, null: false, default: 1
      t.json :stats, null: false, default: {}
      t.json :elements, null: false, default: {}
      t.json :status_immune, null: false, default: []
      t.json :ai_script, null: false, default: []
      t.json :drops, null: false, default: []
      t.integer :exp, null: false, default: 0
      t.integer :gil, null: false, default: 0
      t.integer :abp, null: false, default: 0
      t.text :description
      book_art(t)
      t.timestamps
      t.index %i[world_id slug], unique: true
    end
  end

  private

  # §3.3 / §8: an image slot (Active Storage) plus a variant recipe, and the
  # columns the later generation pipeline will fill.
  def book_art(t)
    t.json :variant, null: false, default: {}
    t.integer :image_seed
    t.text :image_prompt
  end
end
