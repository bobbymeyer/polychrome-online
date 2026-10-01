# frozen_string_literal: true

module Generators
  # What a template makes over many seeds, not one: the report a world
  # builder reads before players find the thin spots (docs/STORY.md, item 4;
  # Compton's "possibility space", Smith's expressive range). Pure: it rolls
  # the generators it's given and counts what came out.
  #
  #   Report.town(template:, tables:, seeds: 1..100)
  #   Report.dungeon(template:, tables:, encounters:, seeds: 1..100, lore:, family_names:)
  #
  # A dungeon's past (Provenance) is rolled as it is for one the world's
  # history never saw, from the world's lore: what it was, and how it fell.
  #
  # Both return { "rolls", "sizes" => { what => [min, mean, max] },
  #   "shares" => { what => { value => percent } }, "placeholders" => { what => percent },
  #   "tables" => { kind => { "rows", "drawn" => { label => count }, "never" => [labels] } }, ... }
  module Report
    TOWN_PLACEHOLDERS = { "town name" => ->(t) { t["name"] == "Nameless Town" ? 1 : 0 },
                          "townsperson's name" => ->(t) { t["npcs"].count { |n| n["name"].start_with?("Stranger ") } },
                          "hook" => ->(t) { t["npcs"].count { |n| n["hook"].nil? } } }.freeze
    DUNGEON_PLACEHOLDERS = { "dungeon name" => ->(d) { d["name"] == "Nameless Depths" ? 1 : 0 },
                             "room name" => ->(d) { d["rooms"].count { |r| r["name"].match?(/\ARoom \d+\z/) } },
                             "event" => ->(d) { d["rooms"].count { |r| r["decision"]["text"] == "Something stirs in the dark." } },
                             "fork cost" => ->(d) { d["rooms"].count { |r| r["decision"]["text"] == "The way is hard." } } }.freeze

    module_function

    def town(template:, tables:, seeds: 1..100)
      towns = seeds.map { |seed| Town.generate(seed: seed, template: template, tables: tables) }
      npcs = towns.flat_map { |t| t["npcs"] }
      {
        "rolls" => towns.size,
        "sizes" => { "townsfolk" => spread(towns.map { |t| t["npcs"].size }),
                     "stock" => spread(towns.map { |t| t["stock"].size }),
                     "buildings" => spread(towns.map { |t| t["skyline"].size }) },
        "shares" => { "services" => percents(towns.flat_map { |t| t["services"].map { |s| s["kind"] } }, towns.size) },
        "placeholders" => placeholders(towns, TOWN_PLACEHOLDERS, "townsperson's name" => npcs.size, "hook" => npcs.size),
        "tables" => usage(tables,
                          "town_names" => towns.map { |t| t["name"] },
                          "names" => npcs.map { |n| n["name"] },
                          "hooks" => npcs.filter_map { |n| n["hook"] },
                          "pasts" => npcs.filter_map { |n| n["past"] },
                          "nows" => npcs.filter_map { |n| n["now"] },
                          "service_names" => towns.flat_map { |t| t["services"].map { |s| s["name"] } },
                          "buildings" => towns.flat_map { |t| t["skyline"].filter_map { |b| b["label"] } },
                          "stock" => towns.flat_map { |t| t["stock"] })
      }
    end

    def dungeon(template:, tables:, encounters:, seeds: 1..100, lore: Lore.empty, family_names: [])
      given = tables.fetch("names", []).filter_map { |e| e["text"] }
      dungeons = seeds.map do |seed|
        rolled = Dungeon.generate(seed: seed, template: template, encounters: encounters, tables: tables)
        past = Provenance.past_for(seed: seed, name: rolled["name"], kind: "dungeon", given_names: given, family_names: family_names, lore: lore)
        rolled.merge("past" => past || {})
      end
      pasts = dungeons.map { |d| d["past"] }
      rooms = dungeons.flat_map { |d| d["rooms"] }
      decisions = rooms.map { |r| r["decision"] }
      forks = dungeons.flat_map { |d| d["rooms"].select { |r| r["decision"]["kind"] == "fork" }.map { |r| costly_path(d, r) } }
      locks = dungeons.map { |d| d["paths"].filter_map { |p| p.dig("lock", "id") }.uniq.size }
      {
        "rolls" => dungeons.size,
        "sizes" => { "rooms" => spread(dungeons.map { |d| d["rooms"].size }),
                     "paths" => spread(dungeons.map { |d| d["paths"].size }),
                     "steps to the boss" => spread(dungeons.map { |d| d["rooms"].find { |r| r["key"] == d["boss"] }["depth"] }) },
        "shares" => { "decisions" => percents(decisions.map { |d| d["kind"] }, decisions.size),
                      "forks" => percents(forks.map { |p| p["gain"] || "buys nothing" }, forks.size),
                      "fork costs" => percents(forks.map { |p| p["cost"].to_s.match?(/\)\s*\z/) ? "the game takes" : "the GM plays out" }, forks.size),
                      "what they were" => percents(pasts.map { |p| p["was"] || "nothing in particular" }, pasts.size),
                      "how they fell" => percents(pasts.map { |p| p.dig("fall", "kind") || "still standing" }, pasts.size) },
        "lore" => { "pasts" => lore.fetch("pasts", {}).keys - pasts.filter_map { |p| p["was"] },
                    "falls" => lore.fetch("falls", {}).keys - pasts.filter_map { |p| p.dig("fall", "kind") } },
        "placeholders" => placeholders(dungeons, DUNGEON_PLACEHOLDERS, "room name" => rooms.size - dungeons.size,
                                                                       "event" => decisions.count { |d| d["kind"] == "event" },
                                                                       "fork cost" => forks.size),
        "locks" => { "asked" => template.fetch("locks", 0).to_i * dungeons.size, "placed" => locks.sum },
        "tables" => usage(tables,
                          "dungeon_names" => dungeons.map { |d| d["name"] },
                          "rooms" => rooms.map { |r| r["name"] },
                          "room_events" => decisions.filter_map { |d| d["text"] if d["kind"] == "event" },
                          "forks" => decisions.filter_map { |d| d["text"] if d["kind"] == "fork" },
                          "treasure" => decisions.filter_map { |d| d["item"] || ("#{d['gil']} gil" if d["gil"]) if d["kind"] == "treasure" },
                          "locks" => dungeons.flat_map { |d| d["paths"].filter_map { |p| p.dig("lock", "name") }.uniq })
      }
    end

    # [min, mean to one place, max].
    def spread(values)
      return [ 0, 0, 0 ] if values.empty?

      [ values.min, (values.sum.to_f / values.size).round(1), values.max ]
    end

    # { value => percent of `out_of` }, most common first.
    def percents(values, out_of)
      return {} if out_of.zero?

      values.tally.sort_by { |value, n| [ -n, value.to_s ] }.to_h { |value, n| [ value, (100.0 * n / out_of).round ] }
    end

    # { what => percent of its slots that came out as the generator's stand-in }.
    def placeholders(rolls, counters, out_of = {})
      counters.to_h do |what, counter|
        slots = out_of.fetch(what, rolls.size)
        [ what, slots.zero? ? 0 : (100.0 * rolls.sum { |roll| counter.call(roll) } / slots).round ]
      end
    end

    # For each kind of table the template draws on: how often each row came
    # up, and the rows that never did.
    def usage(tables, drawn)
      drawn.each_with_object({}) do |(kind, values), out|
        rows = tables.fetch(kind, [])
        next if rows.empty?

        labels = rows.map { |row| label(row) }.uniq
        counts = values.tally
        out[kind] = { "rows" => labels.size,
                      "drawn" => labels.to_h { |l| [ l, counts.fetch(l, 0) ] }.sort_by { |l, n| [ -n, l ] }.to_h,
                      "never" => labels.reject { |l| counts.key?(l) } }
      end
    end

    def label(row)
      row["text"] || row["item"] || "#{row['gil']} gil"
    end

    def costly_path(dungeon, room)
      dungeon["paths"].find { |p| p["key"] == room["decision"]["costly_path"] } || {}
    end
  end
end
