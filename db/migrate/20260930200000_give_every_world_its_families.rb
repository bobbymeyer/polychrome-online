# frozen_string_literal: true

# A history's families are named from the world's Families table; the
# names the game used to fall back on were taken away with the rest of its
# lore (GiveEveryWorldItsLore), and no world had the table. Every world
# without one gets those names as a table it can edit.
class GiveEveryWorldItsFamilies < ActiveRecord::Migration[8.1]
  NAMES = %w[Vell Marrow Asher Crane Dunmore Hale Pike Rook Thorne Wick Briar Coldwell Fenwick Hargrave Lark Moss Oakes Sallow Tennant Garrow].freeze

  def up
    now = Time.current
    entries = NAMES.map { |name| { "text" => name } }.to_json
    select_values("SELECT id FROM worlds").each do |world_id|
      next if select_value("SELECT 1 FROM generator_tables WHERE world_id = #{Integer(world_id)} AND kind = 'families'")

      slug = select_value("SELECT 1 FROM generator_tables WHERE world_id = #{Integer(world_id)} AND slug = 'family_names'") ? "families_#{world_id}" : "family_names"
      execute(<<~SQL)
        INSERT INTO generator_tables (world_id, slug, name, kind, entries, variant, created_at, updated_at)
        VALUES (#{Integer(world_id)}, #{quote(slug)}, 'Families', 'families', #{quote(entries)}, '{}', #{quote(now)}, #{quote(now)})
      SQL
    end
  end

  def down; end
end
