# frozen_string_literal: true

# Each of the Just Seven's dungeons gets an encounter table of its own,
# themed to it (db/seeds/campaigns/just_seven/books.rb DEEPS). They all
# shared five_rooms, which has no table at all, so the elaboration dial
# could only ever add treasure, events and traps to them: Dungeon.possible
# drops "encounter" when there is nothing to fight.
#
# The seven tables and their templates go into Oda's books, then a campaign
# already under way has each dungeon moved onto its own template.
#
# This is safe for the pinned stories, and here is why: Generators::Dungeon
# settles the room count, the edges and the depths from the template's
# `rooms` and `loops` and the stored seed BEFORE it draws a single name, and
# every new template carries the same FIVE_ROOMS config. So the room keys
# and the corridor come out identical, and `pins` and `added_rooms` hang off
# those keys. Only an un-pinned room's rolled name could move, and in these
# dungeons every room is pinned.
class GiveEachDungeonItsOwnTable < ActiveRecord::Migration[8.1]
  def up
    world = World.find_by(slug: "oda") or return

    require Rails.root.join("db/seeds/campaigns/just_seven").to_s
    Seeds::JustSeven.add_books(world)

    # The dungeon's place on the island -> the template it should be on.
    wanted = Seeds::JustSeven::PLACES.filter_map do |name, attrs|
      [ name, attrs[:template] ] if attrs[:kind] == "dungeon" && attrs[:template]
    end.to_h
    templates = world.location_templates.where(slug: wanted.values).index_by(&:slug)

    # Matched on the LOCATION's own name, not its place on the map. The
    # seeder writes the place's name into overrides["name"] when it makes
    # the dungeon, and that is stable; the map node beside it is a row a GM
    # can rename, and on Bobby's own campaign one of them has been (the
    # Sword's node reads "The Lighthouse", which is what the city calls it).
    world.campaigns.find_each do |campaign|
      by_name = campaign.locations.includes(:location_template).index_by { |location| location.overrides["name"] }
      wanted.each do |place, slug|
        template = templates[slug] or next
        location = by_name[place] or next
        next if location.location_template_id == template.id

        location.update_columns(location_template_id: template.id)
      end
    end
  end

  def down
    # Forward only: the tables stay in the books, and a GM may have pointed
    # a dungeon somewhere of their own by now.
  end
end
