# frozen_string_literal: true

# The island's roads rolled nothing: every map edge the Just Seven seeded
# was made without an encounter table, so travelling between the tiers was
# always quiet (Campaign::Travelling only rolls when edge.encounter_table is
# there). And the city itself had none, which also meant the "ambush" hard
# move couldn't be called up here -- Outcome#ambush! rolls on the place's own
# table and otherwise just says "Nothing comes. This time."
#
# So: the four ways tables into Oda's books, each road pointed at the one
# that matches its ground, and island_city given the streets.
#
# The roads' states are left alone. An open road rolls on a quarter of
# crossings and a dangerous one on all of them, so changing a state would
# change the campaign's pacing rather than fill a hole in it.
class GiveTheRoadsAndTheCityTheirTables < ActiveRecord::Migration[8.1]
  def up
    world = World.find_by(slug: "oda") or return

    require Rails.root.join("db/seeds/campaigns/just_seven").to_s
    Seeds::JustSeven.add_books(world)
    tables = world.encounter_tables.where(slug: Seeds::JustSeven::WAYS.keys.map(&:to_s)).index_by(&:slug)

    # The city's own table has to be set by hand. add_books only ADDS what's
    # missing (Seeds::Setting#upsert writes an existing entry only when
    # overwriting), and island_city has been in the books since the campaign
    # was written -- so the encounter_table now on it in LOCATION_TEMPLATES
    # would never reach the row. The seven dungeon templates were new, which
    # is why their own migration didn't have to do this.
    city = world.location_templates.find_by(slug: "island_city")
    streets = tables["the_streets"]
    city.update_columns(encounter_table_id: streets.id) if city && streets && city.encounter_table_id != streets.id

    # Both ends by name, either way round: a road is undirected here.
    wanted = Seeds::JustSeven::ROADS.filter_map do |from, to, attrs|
      [ [ from, to ].sort, attrs[:encounters] ] if attrs[:encounters]
    end.to_h

    world.campaigns.find_each do |campaign|
      # Matched on the LOCATION's name where there is one, as the dungeons'
      # own migration is: a map node is a row a GM can rename.
      named = campaign.map_nodes.includes(:location).to_h do |node|
        [ node.id, node.location&.overrides&.dig("name") || node.name ]
      end
      campaign.map_edges.find_each do |edge|
        slug = wanted[[ named[edge.from_node_id], named[edge.to_node_id] ].sort] or next
        table = tables[slug] or next
        next if edge.encounter_table_id == table.id

        edge.update_columns(encounter_table_id: table.id)
      end
    end
  end

  def down
    # Forward only: the tables stay in the books, and a GM may have pointed
    # a road somewhere of their own by now.
  end
end
