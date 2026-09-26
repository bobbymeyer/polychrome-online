# frozen_string_literal: true

# The Encounter Tables book (docs/HANDOFF.md §2, §4) and each campaign's
# pointcrawl map (§4, §7).
class CreateMap < ActiveRecord::Migration[8.1]
  def change
    create_table :encounter_tables do |t|
      t.references :world, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :name, null: false
      t.string :terrain, null: false
      t.integer :tier, null: false, default: 1
      # [{ "weight" => 3, "monsters" => { "goblin" => 3 } }, ...]
      t.json :entries, null: false, default: []
      t.text :description
      t.json :variant, null: false, default: {}
      t.integer :image_seed
      t.text :image_prompt
      t.timestamps
      t.index %i[world_id slug], unique: true
    end

    create_table :map_nodes do |t|
      t.references :campaign, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "field"
      # Position in the map's 1000 x 700 SVG space.
      t.integer :x, null: false
      t.integer :y, null: false
      t.boolean :visible, null: false, default: false
      t.text :notes
      t.timestamps
    end

    create_table :map_edges do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :from_node, null: false, foreign_key: { to_table: :map_nodes }
      t.references :to_node, null: false, foreign_key: { to_table: :map_nodes }
      t.string :state, null: false, default: "open"
      t.references :encounter_table, foreign_key: true
      t.text :travel_event
      t.timestamps
    end

    # Where the party is, the RNG state for travel encounters (seeded like a
    # battle's), and an encounter rolled but not yet started or waved off.
    add_reference :campaigns, :current_node, foreign_key: { to_table: :map_nodes }
    add_column :campaigns, :rng, :integer, null: false, default: 0
    add_column :campaigns, :pending_encounter, :json
  end
end
