# frozen_string_literal: true

# Bobby's kaiju-mecha campaign is The Just Seven now; it was first seeded
# as Dead Calm. This follows it in a database that has the old name: the
# campaign (where its GM hasn't renamed it), its flag, and the arrival and
# complication rows in Oda's tables that ask for that flag. A row a GM has
# rewritten keeps its words; only the flag it asks for changes.
class RenameDeadCalmToTheJustSeven < ActiveRecord::Migration[8.1]
  TABLES = { "dead_calm_arrivals" => "just_seven_arrivals", "dead_calm_complications" => "just_seven_complications" }.freeze

  def up
    world = World.find_by(slug: "oda") or return

    world.campaigns.where(name: "Dead Calm").update_all(name: "The Just Seven")
    Flag.where(campaign_id: world.campaigns.select(:id), key: "dead_calm").find_each do |flag|
      next if Flag.exists?(campaign_id: flag.campaign_id, key: "just_seven")

      flag.update_columns(key: "just_seven", note: flag.note.to_s.gsub("Dead Calm", "The Just Seven").gsub("DeadCalm", "JustSeven"))
    end
    TABLES.each do |old, slug|
      table = world.generator_tables.find_by(slug: old) or next
      next if world.generator_tables.exists?(slug: slug)

      entries = table.entries.map { |entry| entry.is_a?(Hash) && entry["when"] ? entry.merge("when" => entry["when"].gsub(/\bdead_calm\b/, "just_seven")) : entry }
      table.update_columns(slug: slug, name: table.name.sub(/\ADead Calm\b/, "Just Seven"), entries: entries)
    end
  end

  def down
    # The seed writes the new name; nothing goes back.
  end
end
