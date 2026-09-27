# Town and dungeon names were one kind, so a template drawing on every table
# could name a village "Sealed Castle". Split them, by which templates use
# each table (a table only dungeons draw on is dungeon names).
class SplitPlaceNameTables < ActiveRecord::Migration[8.1]
  def up
    select_rows("SELECT id, world_id, slug FROM generator_tables WHERE kind = 'place_names'").each do |id, world_id, slug|
      kinds = select_rows("SELECT kind, config FROM location_templates WHERE world_id = #{Integer(world_id)}").filter_map do |kind, config|
        kind if JSON.parse(config.to_s.presence || "{}").fetch("tables", []).include?(slug)
      end.uniq
      kind = kinds == [ "dungeon" ] || (kinds.empty? && slug.include?("dungeon")) ? "dungeon_names" : "town_names"
      execute "UPDATE generator_tables SET kind = '#{kind}' WHERE id = #{Integer(id)}"
    end
  end

  def down
    execute "UPDATE generator_tables SET kind = 'place_names' WHERE kind IN ('town_names', 'dungeon_names')"
  end
end
