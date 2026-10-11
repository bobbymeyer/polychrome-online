# frozen_string_literal: true

# A repair. 20261010210000 moved the seven dungeons onto composed room names
# and dropped the shared mine_rooms table from their templates -- but the
# room_qualities table it composes with was written into Oda's own seeds,
# and that migration only calls Seeds::JustSeven.add_books, which seeds the
# campaign's tables and nothing else. So the parts arrived, the qualities
# never did, Dungeon.composed? stayed false, the flat table was gone, and
# every elaborated room on the island came out "Side room 1".
#
# The qualities now live in the campaign's own GENERATOR_TABLES, so add_books
# is self-sufficient and this just runs it again. Idempotent: it adds what's
# missing and leaves the rest alone.
#
# Dungeon.composed? also stopped requiring qualities, so parts alone compose
# to "The ballast gallery" -- a half-configured dungeon reads plainly now
# instead of falling through to a table it may not have.
class SeedTheRoomQualities < ActiveRecord::Migration[8.1]
  def up
    world = World.find_by(slug: "oda") or return

    require Rails.root.join("db/seeds/campaigns/just_seven").to_s
    Seeds::JustSeven.add_books(world)

    Seeds::JustSeven::DEEPS.each_value do |deep|
      template = world.location_templates.find_by(slug: deep.fetch(:template).to_s) or next
      tables = Seeds::JustSeven.five_rooms_tables(deep.fetch(:parts))
      next if template.config["tables"] == tables

      template.update_columns(config: template.config.merge("tables" => tables))
    end
  end

  def down
    # Forward only.
  end
end
