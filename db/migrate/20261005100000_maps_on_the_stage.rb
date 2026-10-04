# frozen_string_literal: true

# Maps (docs/HANDOFF.md §7, "Maps"): a setting's atlas is several maps, each
# a 16:9 picture with places and child maps on it, a parent, and siblings
# off its edges by direction (WorldMap, WorldMapLink); a campaign gets its
# own copies (Map, MapLink), as it gets places. Every place and road is on
# one map now, and the drawing space is 16:9 (1600 × 900, from 1000 × 700):
# positions are scaled into it. A road can bend through waypoints to follow
# the picture. The stage shows a map when the GM says so (stage_view,
# shown_map_id).
class MapsOnTheStage < ActiveRecord::Migration[8.1]
  def up
    create_table :world_maps do |t|
      t.references :world, null: false, foreign_key: false
      t.string :name, null: false
      t.references :parent, foreign_key: false
      t.integer :x
      t.integer :y
      t.text :description
      t.timestamps
    end
    create_table :world_map_links do |t|
      t.references :world, null: false, foreign_key: false
      t.references :from_map, null: false, foreign_key: false
      t.references :to_map, null: false, foreign_key: false
      t.string :direction, null: false
      t.timestamps
    end
    create_table :maps do |t|
      t.references :campaign, null: false, foreign_key: false
      t.references :world_map, foreign_key: false
      t.string :name, null: false
      t.references :parent, foreign_key: false
      t.integer :x
      t.integer :y
      t.text :description
      t.timestamps
    end
    create_table :map_links do |t|
      t.references :campaign, null: false, foreign_key: false
      t.references :from_map, null: false, foreign_key: false
      t.references :to_map, null: false, foreign_key: false
      t.string :direction, null: false
      t.timestamps
    end
    add_reference :world_places, :world_map, foreign_key: false
    add_reference :map_nodes, :map, foreign_key: false
    add_column :world_routes, :waypoints, :json, null: false, default: []
    add_column :map_edges, :waypoints, :json, null: false, default: []
    add_reference :campaigns, :shown_map, foreign_key: false
    add_column :campaigns, :stage_view, :string, null: false, default: "here"

    # Into the 16:9 space, keeping the layout.
    execute "UPDATE world_places SET x = CAST(ROUND(x * 1.6) AS INTEGER), y = CAST(ROUND(y * 900.0 / 700) AS INTEGER)"
    execute "UPDATE map_nodes SET x = CAST(ROUND(x * 1.6) AS INTEGER), y = CAST(ROUND(y * 900.0 / 700) AS INTEGER)"

    # One root map a world, and one a campaign, with everything on it.
    now = connection.quoted_date(Time.current)
    select_all("SELECT id, name FROM worlds").each do |world|
      execute "INSERT INTO world_maps (world_id, name, created_at, updated_at) VALUES (#{world['id']}, #{connection.quote(world['name'])}, '#{now}', '#{now}')"
      root = select_value("SELECT id FROM world_maps WHERE world_id = #{world['id']} ORDER BY id LIMIT 1")
      execute "UPDATE world_places SET world_map_id = #{root} WHERE world_id = #{world['id']}"
      select_all("SELECT id, name FROM campaigns WHERE world_id = #{world['id']}").each do |campaign|
        execute "INSERT INTO maps (campaign_id, world_map_id, name, created_at, updated_at) VALUES (#{campaign['id']}, #{root}, #{connection.quote(world['name'])}, '#{now}', '#{now}')"
        map = select_value("SELECT id FROM maps WHERE campaign_id = #{campaign['id']} ORDER BY id LIMIT 1")
        execute "UPDATE map_nodes SET map_id = #{map} WHERE campaign_id = #{campaign['id']}"
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
