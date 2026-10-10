# frozen_string_literal: true

# The Giant Battle is built (docs/ODA.md, The Just Seven): Swirl-Pool's
# seven stations and Fleet Crasher go into Oda's books (only what's
# missing), and a campaign already started gains Landfall, the fight
# itself, past the Head's twist. The endings are gone from the notes, so
# the GM's checklist loses its "ending" flag where it's still as seeded.
class BringInTheGiantBattle < ActiveRecord::Migration[8.1]
  def up
    world = World.find_by(slug: "oda") or return

    require Rails.root.join("db/seeds/campaigns/just_seven").to_s
    Seeds::JustSeven.add_books(world)
    landfall = Seeds::JustSeven::PLACES.fetch("Founders' Hill")[:twist].find { |twist| twist[:name] == "Landfall" }

    world.campaigns.find_each do |campaign|
      hill = campaign.map_nodes.find_by(name: "Founders' Hill")&.location or next
      added = Array(hill.overrides["added_rooms"])
      next if added.empty? || added.any? { |room| room["name"] == "Landfall" }

      room = { "key" => "added-#{added.size + 1}", "name" => "Landfall", "decision" => landfall[:decision].deep_stringify_keys,
               "connect" => added.last["key"] }
      hill.update_columns(overrides: hill.overrides.merge("added_rooms" => added + [ room ]))
      campaign.flags.where(key: "ending").where("note LIKE ?", "Bind (keep the masks%").delete_all
    end
  end

  def down
    # Forward only: the books keep their entries, and the room is the GM's now.
  end
end
