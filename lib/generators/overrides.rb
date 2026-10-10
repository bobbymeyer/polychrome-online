# frozen_string_literal: true

module Generators
  # GM diffs on top of a generated location (docs/HANDOFF.md §7: "GM diffs
  # are overrides on top"). Pure: generated location + overrides -> what the
  # table sees. Rerolling changes the seed, and the overrides stay.
  #
  # overrides: {
  #   "name"        => "Tule",                            rename
  #   "pins"        => { "service-inn" => {...}, "room-3" => {...} }
  #                    pinned elements survive rerolls; for a room, only
  #                    its name and decision are pinned, not its place
  #   "stock"       => ["potion", ...]                    replaces the shop's stock
  #   "boss"        => { "ogre" => 1 }                    who waits in the boss room
  #   "added_rooms" => [{ "key", "name", "decision", "connect" }]
  #   "moved_rooms" => { "room-3" => [x, y] }              rooms dragged off where they rolled
  #   "added_paths" => [["room-1", "room-4"]]              ways the GM joined
  #   "removed_paths" => ["path-room-1-room-2"]            ways the GM cut
  # }
  #
  # The last three are the dungeon's shape, and they go last for a reason:
  # a path can join an added room, and a move can shift one, so the rooms
  # have to all be there first.
  module Overrides
    ADDED_OFFSET = 70

    module_function

    def apply(generated, overrides)
      location = deep_dup(generated)
      location["name"] = overrides["name"] if overrides["name"].to_s.strip != ""
      pins = overrides.fetch("pins", {})
      location["kind"] == "dungeon" ? dungeon(location, pins, overrides) : town(location, pins, overrides)
      location
    end

    def town(location, pins, overrides)
      location["services"] = location["services"].map { |service| pins.fetch(service["key"], service) }
      location["stock"] = overrides["stock"] if overrides["stock"]
    end

    def dungeon(location, pins, overrides)
      location["rooms"].each do |room|
        pinned = pins[room["key"]]
        room.merge!(pinned.slice("name", "decision")) if pinned
      end
      boss = location["rooms"].find { |room| room["key"] == location["boss"] }
      boss["decision"] = boss["decision"].slice("who").merge("kind" => "boss", "monsters" => overrides["boss"]) if boss && overrides["boss"]
      overrides.fetch("added_rooms", []).each { |room| add_room(location, room) }
      cut_paths(location, overrides.fetch("removed_paths", []))
      join_paths(location, overrides.fetch("added_paths", []))
      move_rooms(location, overrides.fetch("moved_rooms", {}))
    end

    # Ways the GM cut, by path key. A key the roll no longer produces is
    # simply not there to drop.
    def cut_paths(location, keys)
      return if keys.empty?

      location["paths"].reject! { |path| keys.include?(path["key"]) }
    end

    # Ways the GM joined. A pair naming a room this roll didn't produce is
    # dropped rather than drawn to nowhere: the room count itself can change
    # between rolls, and a half-drawn path would break #neighbours.
    def join_paths(location, pairs)
      keys = location["rooms"].map { |room| room["key"] }
      pairs.each do |from, to|
        next unless keys.include?(from) && keys.include?(to)
        next if location["paths"].any? { |path| [ path["from"], path["to"] ].sort == [ from, to ].sort }

        location["paths"] << { "key" => added_path_key(from, to), "from" => from, "to" => to, "added" => true }
      end
    end

    # Rooms dragged off where they rolled. Last, so it reaches added rooms too.
    def move_rooms(location, places)
      return if places.empty?

      location["rooms"].each do |room|
        at = places[room["key"]] or next
        room["x"], room["y"] = at.map(&:to_i)
      end
    end

    def added_path_key(from, to)
      "path-added-#{[ from, to ].sort.join('-')}"
    end

    # A hand-authored room hangs off an existing one, drawn just beside it.
    def add_room(location, spec)
      anchor = location["rooms"].find { |room| room["key"] == spec["connect"] } or return
      location["rooms"] << {
        "key" => spec["key"], "name" => spec["name"], "decision" => spec["decision"], "added" => true,
        "depth" => anchor["depth"] + 1,
        "x" => [ anchor["x"] + ADDED_OFFSET, Dungeon::WIDTH - 20 ].min,
        "y" => [ anchor["y"] + ADDED_OFFSET, Dungeon::HEIGHT - 20 ].min
      }
      location["paths"] << { "key" => "path-#{spec['key']}", "from" => anchor["key"], "to" => spec["key"] }
    end

    def deep_dup(value)
      case value
      when Hash then value.to_h { |k, v| [ k, deep_dup(v) ] }
      when Array then value.map { |v| deep_dup(v) }
      else value
      end
    end
  end
end
