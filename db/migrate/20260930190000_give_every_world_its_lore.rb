# frozen_string_literal: true

# What histories and the pasts of places are made of (trades, what dungeons
# were, how places fall, quarrels and the rest) was the game's own; now it's
# each world's, in its generator tables (Generators::Lore). Every world made
# before gets what it had been using, as tables it can now edit.
class GiveEveryWorldItsLore < ActiveRecord::Migration[8.1]
  NAMES = { "trades" => "Trades", "pasts" => "What dungeons were", "falls" => "How places fall", "quarrels" => "Quarrels",
            "betrayals" => "Betrayals", "fortunes" => "Good fortune", "waters" => "Waters", "owners" => "Changing hands",
            "sightings" => "Sightings", "raids" => "Raided roads" }.freeze

  def up
    now = Time.current
    tables = Generators::Lore.to_tables(Generators::Lore::STARTER)
    select_values("SELECT id FROM worlds").each do |world_id|
      have = select_values("SELECT kind FROM generator_tables WHERE world_id = #{Integer(world_id)}")
      tables.each do |kind, entries|
        next if have.include?(kind)

        execute(<<~SQL)
          INSERT INTO generator_tables (world_id, slug, name, kind, entries, variant, created_at, updated_at)
          VALUES (#{Integer(world_id)}, #{quote("lore_#{kind}")}, #{quote(NAMES.fetch(kind))}, #{quote(kind)}, #{quote(entries.to_json)}, '{}',
                  #{quote(now)}, #{quote(now)})
        SQL
      end
    end
  end

  def down
    execute("DELETE FROM generator_tables WHERE kind IN (#{NAMES.keys.map { |k| quote(k) }.join(', ')})")
  end
end
