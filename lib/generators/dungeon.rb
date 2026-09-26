# frozen_string_literal: true

module Generators
  # The dungeon generator (docs/HANDOFF.md §7): a room graph that branches and
  # loops, laid out as a floorplan. A dungeon is a nested pointcrawl, and
  # every room carries a decision: an encounter, an event, treasure, or a
  # fork with a visible cost. The deepest room holds the boss. "The
  # generator's job is generating decisions, not rooms."
  #
  # template: { "rooms" => [min, max], "loops" => n,
  #             "decisions" => { "encounter" => 4, "event" => 2, "treasure" => 2, "fork" => 1 },
  #             "boss" => { "goblin_chief" => 1 } }            optional
  # encounters: encounter-table entries ([{ "weight", "monsters" }])
  # tables:   { "place_names" | "rooms" | "room_events" | "forks" | "treasure" => [entries] }
  #
  # Pure: same seed, same dungeon.
  module Dungeon
    DECISIONS = %w[encounter event treasure fork boss].freeze
    WIDTH = 1000
    HEIGHT = 700
    MAX_EXITS = 3

    module_function

    def generate(seed:, template:, encounters:, tables:)
      pool = Pool.new(Battle::Rng.new(seed))
      min, max = template.fetch("rooms", [ 6, 9 ])
      count = pool.between([ min, 2 ].max, [ max, min, 2 ].max)
      edges = tree(pool, count)
      add_loops(pool, edges, count, template.fetch("loops", 1).to_i)
      depths = depths(edges, count)
      boss = (0...count).max_by { |i| [ depths[i], i ] }

      names = pool.sample(tables.fetch("rooms", []), count)
      rooms = Array.new(count) do |i|
        {
          "key" => "room-#{i}",
          "name" => i.zero? ? "Entrance" : (names[i]&.fetch("text") || "Room #{i}"),
          "depth" => depths[i]
        }
      end
      layout(rooms, depths)

      edge_list = edges.map { |a, b| { "key" => "path-#{a}-#{b}", "from" => "room-#{a}", "to" => "room-#{b}" } }
      rooms.each_with_index do |room, i|
        room["decision"] = if i == boss
                             boss_decision(pool, template, encounters)
        else
                             decision(pool, template, encounters, tables, room, i, edges, depths, edge_list)
        end
      end

      {
        "kind" => "dungeon",
        "name" => pool.pick(tables.fetch("place_names", []))&.fetch("text") || "Nameless Depths",
        "rooms" => rooms,
        "paths" => edge_list,
        "entrance" => "room-0",
        "boss" => "room-#{boss}"
      }
    end

    # A random tree: each room joins an earlier room with a free exit.
    def tree(pool, count)
      degree = Hash.new(0)
      (1...count).map do |i|
        open = (0...i).select { |j| degree[j] < MAX_EXITS }
        parent = open[pool.int(open.size)]
        degree[parent] += 1
        degree[i] += 1
        [ parent, i ]
      end
    end

    # Extra passages between rooms at least two steps apart make loops.
    def add_loops(pool, edges, count, loops)
      loops.times do
        depths = depths(edges, count)
        candidates = (0...count).to_a.combination(2).select do |a, b|
          !edges.include?([ a, b ]) && !edges.include?([ b, a ]) && distance(edges, count, a, b) >= 3 &&
            a.positive? && (depths[a] - depths[b]).abs <= 1
        end
        break if candidates.empty?

        edges << candidates[pool.int(candidates.size)]
      end
    end

    def neighbours(edges, room)
      edges.filter_map { |a, b| (b if a == room) || (a if b == room) }
    end

    def depths(edges, count)
      depth = { 0 => 0 }
      queue = [ 0 ]
      while (room = queue.shift)
        neighbours(edges, room).each do |n|
          next if depth.key?(n)

          depth[n] = depth[room] + 1
          queue << n
        end
      end
      Array.new(count) { |i| depth.fetch(i) }
    end

    def distance(edges, count, from, to)
      depth = { from => 0 }
      queue = [ from ]
      while (room = queue.shift)
        return depth[room] if room == to

        neighbours(edges, room).each do |n|
          next if depth.key?(n)

          depth[n] = depth[room] + 1
          queue << n
        end
      end
      count
    end

    # Floorplan: depth runs left to right, rooms of the same depth stack.
    def layout(rooms, depths)
      max_depth = [ depths.max, 1 ].max
      rooms.group_by { |r| r["depth"] }.each do |depth, column|
        column.each_with_index do |room, i|
          room["x"] = 80 + depth * (WIDTH - 160) / max_depth
          room["y"] = (HEIGHT * (i + 1) / (column.size + 1))
        end
      end
    end

    # Rooms with more than one way onward may hold a fork: one of those ways
    # gets a visible cost.
    def decision(pool, template, encounters, tables, room, index, edges, depths, edge_list)
      weights = template.fetch("decisions", { "encounter" => 4, "event" => 2, "treasure" => 2, "fork" => 1 }).dup
      onward = neighbours(edges, index).select { |n| depths[n] > depths[index] }
      weights.delete("fork") if onward.size < 2
      weights.delete("encounter") if encounters.empty?
      weights.delete("treasure") if tables.fetch("treasure", []).empty?
      weights = { "event" => 1 } if weights.values.sum.zero?

      case pool.choose(weights)
      when "encounter"
        { "kind" => "encounter", "monsters" => pool.pick(encounters)["monsters"] }
      when "treasure"
        { "kind" => "treasure", "item" => pool.pick(tables["treasure"])["item"] }
      when "fork"
        costly = onward[pool.int(onward.size)]
        path = edge_list.find { |e| [ e["from"], e["to"] ].sort == [ room["key"], "room-#{costly}" ].sort }
        cost = pool.pick(tables.fetch("forks", []))&.fetch("text") || "The way is hard."
        path["cost"] = cost
        { "kind" => "fork", "text" => cost, "costly_path" => path["key"] }
      else
        { "kind" => "event", "text" => pool.pick(tables.fetch("room_events", []))&.fetch("text") || "Something stirs in the dark." }
      end
    end

    def boss_decision(pool, template, encounters)
      chosen = template["boss"]
      monsters = chosen && !chosen.empty? ? chosen : encounters.max_by { |e| e["monsters"].values.sum }&.fetch("monsters") || {}
      pool.int(1) # keep the stream shape fixed whether or not a boss is set
      { "kind" => "boss", "monsters" => monsters }
    end
  end
end
