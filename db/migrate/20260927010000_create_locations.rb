# frozen_string_literal: true

# Towns and dungeons (docs/HANDOFF.md §4, §7). Two books: the Gazetteer's
# location templates and the generator tables. Campaign locations store
# only template + seed + GM overrides; what they contain is generated from
# those every time (§12: generated locations are derived, never the source
# of truth).
class CreateLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :generator_tables do |t|
      t.references :world, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :name, null: false
      t.string :kind, null: false
      t.json :entries, null: false, default: []
      t.text :description
      t.json :variant, null: false, default: {}
      t.integer :image_seed
      t.text :image_prompt
      t.timestamps
      t.index %i[world_id slug], unique: true
    end

    create_table :location_templates do |t|
      t.references :world, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :name, null: false
      t.string :kind, null: false
      # Generator settings for the kind (see Generators::Town / ::Dungeon),
      # plus "tables": the generator tables to draw from (all, if empty).
      t.json :config, null: false, default: {}
      t.references :encounter_table, foreign_key: true
      t.text :description
      t.json :variant, null: false, default: {}
      t.integer :image_seed
      t.text :image_prompt
      t.timestamps
      t.index %i[world_id slug], unique: true
    end

    create_table :locations do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :location_template, null: false, foreign_key: true
      t.integer :seed, null: false
      # GM diffs on top of the seed: name, pins, stock, boss, added rooms.
      t.json :overrides, null: false, default: {}
      # Exploration progress in a dungeon: current room, visited, resolved.
      t.json :progress, null: false, default: {}
      t.timestamps
    end

    add_reference :map_nodes, :location, foreign_key: true
    # NPCs a location has made real: pinned from its roster (location_key is
    # the generated slot) or written in by the GM.
    add_reference :npcs, :location, foreign_key: true
    add_column :npcs, :location_key, :string
  end
end
