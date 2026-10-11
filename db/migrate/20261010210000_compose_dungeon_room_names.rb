# frozen_string_literal: true

# Room names were repeating badly: at the dial's third notch the island's
# seven dungeons made 42 rooms between them with 10 distinct names, and five
# of the seven made the identical six rooms in the identical order.
#
# Two causes, and this fixes the half that lives in the data. (The other half
# is the elaboration stream, which now takes the location's name as well as
# its seed -- Generators::Elaboration#stream_for -- and needs no migration.)
#
# All seven drew their names from one twelve-row list of mine names. Now each
# has a vocabulary of its own: its own parts, Oda's shared qualities, and the
# generator composes them (Generators::Dungeon.room_name). A dozen qualities
# against eight parts is about a hundred names per dungeon.
class ComposeDungeonRoomNames < ActiveRecord::Migration[8.1]
  def up
    world = World.find_by(slug: "oda") or return

    require Rails.root.join("db/seeds/campaigns/just_seven").to_s
    Seeds::JustSeven.add_books(world)

    # The templates' `tables` lists have to be written by hand. add_books only
    # ADDS what's missing -- Seeds::Setting#upsert writes an existing entry
    # only when overwriting -- and all seven templates already exist, so the
    # new lists declared in LOCATION_TEMPLATES would never reach the rows and
    # composition would simply never engage. Same trap that would have left
    # island_city without its encounter table.
    Seeds::JustSeven::DEEPS.each_value do |deep|
      template = world.location_templates.find_by(slug: deep.fetch(:template).to_s) or next
      tables = Seeds::JustSeven.five_rooms_tables(deep.fetch(:parts))
      next if template.config["tables"] == tables

      template.update_columns(config: template.config.merge("tables" => tables))
    end
  end

  def down
    # Forward only: the vocabularies stay in the books, and a GM may have
    # ticked tables of their own onto a template by now.
  end
end
