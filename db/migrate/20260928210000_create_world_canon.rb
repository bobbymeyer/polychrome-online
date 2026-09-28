# frozen_string_literal: true

# A setting's canon (docs/HANDOFF.md §2): its places and the roads between
# them, its people, and its lore. Written once in the world; a campaign
# starts with them, and makes them its own.
class CreateWorldCanon < ActiveRecord::Migration[8.1]
  def change
    create_table :world_places do |t|
      t.references :world, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "town"
      t.integer :x, null: false
      t.integer :y, null: false
      t.boolean :known, null: false, default: false
      t.text :description
      t.text :notes
      t.references :location_template, foreign_key: true
      t.integer :seed
      t.timestamps
    end

    create_table :world_routes do |t|
      t.references :world, null: false, foreign_key: true
      t.references :from_place, null: false, foreign_key: { to_table: :world_places }
      t.references :to_place, null: false, foreign_key: { to_table: :world_places }
      t.string :state, null: false, default: "open"
      t.references :encounter_table, foreign_key: true
      t.text :travel_event
      t.timestamps
    end

    create_table :world_figures do |t|
      t.references :world, null: false, foreign_key: true
      t.string :name, null: false
      t.string :title
      t.text :blurb
      t.text :description
      t.text :art_notes
      t.string :colour
      t.references :monster, foreign_key: true
      t.references :world_place, foreign_key: true
      t.timestamps
    end

    create_table :codex_entries do |t|
      t.references :world, null: false, foreign_key: true
      t.string :title, null: false
      t.string :category
      t.text :body
      t.text :gm_notes
      t.boolean :public, null: false, default: true
      t.timestamps
      t.index %i[world_id title], unique: true
    end

    add_reference :map_nodes, :world_place, foreign_key: true
    add_column :map_nodes, :description, :text
    add_reference :map_edges, :world_route, foreign_key: true
    add_reference :npcs, :world_figure, foreign_key: true
  end
end
