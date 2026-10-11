# frozen_string_literal: true

module Generators
  # The dungeon generator (docs/HANDOFF.md §7): a room graph that branches and
  # loops, laid out as a floorplan. A dungeon is a nested pointcrawl, and
  # every room carries a decision: an encounter, an event, treasure, a fork
  # with a visible cost, a trap, or a key. The deepest room holds the boss. "The
  # generator's job is generating decisions, not rooms."
  #
  # Locks and keys come in pairs from the "locks" table, in any flavour: a
  # portal and its crystal, an altar and a goat's skull. A lock sits on a
  # path; its key is a room's decision.
  #
  # template: { "rooms" => [min, max], "loops" => n,
  #             "decisions" => { "encounter" => 4, "event" => 2, "treasure" => 2, "fork" => 1 },
  #             "boss" => { "goblin_chief" => 1 },             optional
  #             "locks" => n }                                   optional, 0–3
  # encounters: encounter-table entries ([{ "weight", "monsters" }])
  # tables:   { "dungeon_names" | "rooms" | "room_events" | "forks" | "treasure" | "locks" | "traps" => [entries] }
  #
  # A trap is a room's decision, written like a fork's cost: "A tripwire and
  # a powder charge (hurt 20)". Only templates that weigh "trap" roll them.
  #
  # Pure: same seed, same dungeon.
  module Dungeon
    DECISIONS = %w[encounter event treasure fork boss key trap].freeze
    DEFAULT_DECISIONS = { "encounter" => 4, "event" => 2, "treasure" => 2, "fork" => 1 }.freeze
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

      # Composed names when the tables are there, else the flat list exactly
      # as before: a template on "rooms" alone must roll what it always did.
      if composed?(tables)
        taken = []
        names = Array.new(count) { composed(pool, tables, taken).tap { |name| taken << name } }
      else
        names = pool.sample(tables.fetch("rooms", []), count).map { |row| row&.fetch("text") }
      end
      rooms = Array.new(count) do |i|
        {
          "key" => "room-#{i}",
          "name" => i.zero? ? "Entrance" : (names[i] || "Room #{i}"),
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

      name = pool.pick(tables.fetch("dungeon_names", []))&.fetch("text") || "Nameless Depths"
      add_locks(pool, template.fetch("locks", 0).to_i, tables.fetch("locks", []), rooms, edges, edge_list, boss)
      worth_the_cost(rooms, edges, edge_list, boss)
      {
        "kind" => "dungeon",
        "name" => name,
        "rooms" => rooms,
        "paths" => edge_list,
        "entrance" => "room-0",
        "boss" => "room-#{boss}"
      }
    end

    # Each lock guards a way the party can't get around on the way to the
    # boss: a single path on the route (when loops don't bypass it), or every
    # door into the boss's room, which always works. Its key lies in a room
    # they can reach before it: behind the earlier locks, if there are
    # several. Drawn after everything else, so a template without locks rolls
    # exactly as it did before locks existed.
    def add_locks(pool, count, flavours, rooms, edges, edge_list, boss)
      return if count <= 0 || boss.zero?

      route = route(edges, boss)
      cuts = route.reject { |edge| reachable(edges, [ edge ]).include?(boss) }.map { |edge| [ edge ] }
      doors = edges.each_index.select { |i| edges[i].include?(boss) }
      cuts << doors unless cuts.include?(doors)
      order = ->(cut) { cut.map { |edge| route.index(edge) || route.size }.min }
      chosen = pool.sample(cuts.map { |cut| { "cut" => cut } }, count).map { |c| c["cut"] }.sort_by(&order)
      taken = [ 0, boss ]
      i = 0
      while i < chosen.size
        cut = chosen[i]
        open = reachable(edges, chosen[i..].flatten)
        earlier = i.zero? ? [] : reachable(edges, chosen[(i - 1)..].flatten)
        usable = (open - taken).reject { |room| rooms[room]["decision"]["kind"] == "fork" }.sort
        # Best between the previous lock and this one; anywhere reachable will do.
        between = usable - earlier
        region = between.empty? ? usable : between
        # Nowhere to hide its key (a lock right by the entrance): leave it out.
        next chosen.delete_at(i) if region.empty?

        room = region[pool.int(region.size)]
        flavour = pool.pick_fresh(flavours) || { "text" => "A locked door", "key" => "An old key" }
        lock = { "id" => "lock-#{i + 1}", "name" => flavour["text"], "key_name" => flavour["key"] }
        cut.each { |edge| edge_list[edge]["lock"] = lock }
        rooms[room]["decision"] = { "kind" => "key", "lock" => lock["id"], "name" => flavour["key"] }
        taken << room
        i += 1
      end
    end

    # A fork's cost should buy something, or nobody pays it. The costly way
    # becomes the shortcut to the boss (a way that gets there sooner, when
    # there's another way round), or else the way to treasure that only lies
    # down that side. Draws nothing, so the rest of the dungeon rolls as it
    # did; when neither fits, the cost stays where it fell.
    def worth_the_cost(rooms, edges, edge_list, boss)
      count = rooms.size
      rooms.each_with_index do |room, i|
        decision = room["decision"]
        next unless decision["kind"] == "fork"

        onward = neighbours(edges, i).select { |n| rooms[n]["depth"] > room["depth"] }
        path_to = ->(n) { edge_list[edges.index { |edge| edge.sort == [ i, n ].sort }] }
        gain, costly = shortcut(edges, count, i, onward, boss)
        gain, costly = hoard(rooms, edges, i, onward) unless costly
        next unless costly

        old = edge_list.find { |p| p["key"] == decision["costly_path"] }
        path_to.(costly).merge!("cost" => old.delete("cost"), "gain" => gain)
        decision["costly_path"] = path_to.(costly)["key"]
      end
    end

    # The onward room nearest the boss, if it's strictly nearer than every
    # other way out of the fork (back the way the party came included) and
    # the boss can still be reached without going that way.
    def shortcut(edges, count, from, onward, boss)
      return if onward.size < 2

      near = onward.min_by { |n| [ distance(edges, count, n, boss), n ] }
      others = neighbours(edges, from) - [ near ]
      return unless others.all? { |n| distance(edges, count, n, boss) > distance(edges, count, near, boss) }

      edge = edges.index { |e| e.sort == [ from, near ].sort }
      [ "shortcut", near ] if reachable(edges, [ edge ]).include?(boss)
    end

    # The onward room whose side alone holds treasure.
    def hoard(rooms, edges, from, onward)
      sides = onward.to_h { |n| [ n, beyond(edges, from, n) ] }
      rich = onward.find do |n|
        others = (onward - [ n ]).flat_map { |m| sides[m] }
        (sides[n] - others).any? { |r| rooms[r]["decision"]["kind"] == "treasure" }
      end
      [ "treasure", rich ] if rich
    end

    # Rooms reachable from `start` without going back through `from`.
    def beyond(edges, from, start)
      seen = [ start ]
      queue = [ start ]
      while (room = queue.shift)
        neighbours(edges, room).each do |n|
          next if n == from || seen.include?(n)

          seen << n
          queue << n
        end
      end
      seen
    end

    # The edges (by index) of a shortest way from the entrance to `to`.
    def route(edges, to)
      came_by = { 0 => nil }
      queue = [ 0 ]
      while (room = queue.shift)
        edges.each_with_index do |(a, b), i|
          other = (b if a == room) || (a if b == room)
          next if other.nil? || came_by.key?(other)

          came_by[other] = [ room, i ]
          queue << other
        end
      end
      path = []
      room = to
      while (step = came_by[room])
        room, edge = step
        path.unshift(edge)
      end
      path
    end

    # Rooms reachable from the entrance without crossing the given edges.
    def reachable(edges, blocked)
      seen = [ 0 ]
      queue = [ 0 ]
      while (room = queue.shift)
        edges.each_with_index do |(a, b), i|
          next if blocked.include?(i)

          other = (b if a == room) || (a if b == room)
          next if other.nil? || seen.include?(other)

          seen << other
          queue << other
        end
      end
      seen
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
    # gets a visible cost. A fork is the only kind that needs the graph, so
    # it stays here and the rest is #simple_decision, which
    # Generators::Elaboration rolls its extra rooms from as well.
    #
    # The draws, in order: one #choose, then one more for whichever kind came
    # up (two for a fork). Nothing may change that order -- every dungeon
    # ever rolled is that stream (spec/generators/dungeon_spec rolls 300).
    def decision(pool, template, encounters, tables, room, index, edges, depths, edge_list)
      weights = template.fetch("decisions", DEFAULT_DECISIONS).dup
      onward = neighbours(edges, index).select { |n| depths[n] > depths[index] }
      weights.delete("fork") if onward.size < 2
      weights = possible(weights, encounters, tables)

      kind = pool.choose(weights)
      return simple_decision(pool, kind, encounters, tables) unless kind == "fork"

      costly = onward[pool.int(onward.size)]
      path = edge_list.find { |e| [ e["from"], e["to"] ].sort == [ room["key"], "room-#{costly}" ].sort }
      cost = pool.pick_fresh(tables.fetch("forks", []))&.fetch("text") || "The way is hard."
      path["cost"] = cost
      { "kind" => "fork", "text" => cost, "costly_path" => path["key"] }
    end

    # The kinds a world can actually roll: drop what it has no table for, and
    # fall back to an event when that leaves nothing. Deletion keeps the
    # hash's order, which #choose walks.
    def possible(weights, encounters, tables)
      weights = weights.dup
      weights.delete("encounter") if encounters.empty?
      weights.delete("treasure") if tables.fetch("treasure", []).empty?
      weights.delete("trap") if tables.fetch("traps", []).empty?
      weights.values.sum.zero? ? { "event" => 1 } : weights
    end

    # A room's name. Composed from a part and a quality when the world has
    # given this dungeon both ("The flooded ballast gallery"), else drawn
    # from its flat "rooms" table. A dozen qualities against eight parts is
    # about a hundred names from twenty rows, which is what stops seven
    # dungeons sharing a vocabulary and saying the same thing twice.
    #
    # taken: the names this dungeon has used already. A clash redraws the
    # quality rather than the part, so a dungeon works through its own parts
    # before it starts dressing them differently.
    def room_name(pool, tables, taken = [])
      composed?(tables) ? composed(pool, tables, taken) : pool.pick_fresh(tables.fetch("rooms", []))&.fetch("text")
    end

    # Parts alone are enough: "The ballast gallery". Qualities only dress
    # them. Requiring both meant a template with parts and no qualities fell
    # through to its flat "rooms" table -- and a template that had dropped
    # that table had nothing left, so every room came out "Side room 1". A
    # half-configured dungeon should read plainly, not fail.
    def composed?(tables)
      tables.fetch("room_parts", []).any?
    end

    REDRAWS = 6

    def composed(pool, tables, taken)
      part = pool.pick_fresh(tables.fetch("room_parts", []))&.fetch("text") or return nil
      name = nil
      REDRAWS.times do
        quality = pool.pick_fresh(tables.fetch("room_qualities", []))&.fetch("text")
        name = quality ? "The #{quality} #{part}" : "The #{part}"
        break unless taken.include?(name)
      end
      name
    end

    # Every decision but a fork: one draw, and no need for the room graph.
    def simple_decision(pool, kind, encounters, tables)
      case kind
      when "encounter"
        { "kind" => "encounter", "monsters" => pool.pick(encounters)["monsters"] }
      when "treasure"
        { "kind" => "treasure" }.merge(pool.pick_fresh(tables["treasure"]).slice("item", "gil"))
      when "trap"
        { "kind" => "trap", "text" => pool.pick_fresh(tables["traps"])&.fetch("text") || "A tripwire. (hurt 10)" }
      else
        { "kind" => "event", "text" => pool.pick_fresh(tables.fetch("room_events", []))&.fetch("text") || "Something stirs in the dark." }
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
