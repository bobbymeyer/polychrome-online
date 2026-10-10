# frozen_string_literal: true

module Generators
  # An elaboration scale for a dungeon (0-5): extra rooms and passages grown
  # around the rolled core, two rooms a step, without disturbing it.
  #
  # Why it exists: a seeded campaign pins its story onto the core rooms in
  # order (Seeds::JustSeven pins room-0..room-N onto a corridor), so the core
  # IS the adventure. A dial that reshaped it would throw the plot out of
  # sequence. This one cannot, by construction.
  #
  # THE INVARIANT: the party still passes through every core room, in the
  # same order. Every extra attaches in one of three shapes, and may anchor
  # only to a core room or to an EARLIER extra:
  #
  #   alcove    one edge, to one room          a leaf: no route goes through it
  #   chain     a leaf off a leaf              still leaf-ward
  #   parallel  two edges, to two rooms that   length 2 beside an existing 1,
  #             are ALREADY adjacent           so it never shortens anything
  #
  # So no distance arithmetic and no connectivity check: none of the three can
  # shorten the way between two core rooms, and none can bypass one.
  #
  # Turning the dial up APPENDS rather than reshuffling. Candidate i is rolled
  # from the state left by candidates 1..i-1 and nothing else -- the level is
  # only where the loop stops -- so elab-3 is the same room at level 2 as at
  # level 5, and a pin on it survives the dial moving. Anchoring backwards
  # only is what makes turning the dial down safe: dropping the tail can
  # never orphan what is left.
  module Elaboration
    MAX_LEVEL = 5
    PER_LEVEL = 2

    # Its own stream, never the dungeon's: drawing from the dungeon's pool
    # would change the core roll itself.
    SALT = 0x51AB

    # Not the template's weights. Oda's five_rooms weighs { "event" => 1 }
    # and nothing else -- following it would add ten event rooms, which is
    # depth without complexity. The extra rooms are where the wandering
    # monsters and the loot live; the core keeps saying what the GM pinned.
    # No fork: a fork puts a cost on a path and is tangled up with locks and
    # Dungeon#worth_the_cost on the core route.
    SPREAD = { "encounter" => 4, "treasure" => 3, "event" => 3, "trap" => 2 }.freeze

    SHAPES = { "alcove" => 5, "parallel" => 4, "chain" => 3 }.freeze

    # How far an extra sits from its anchor, and how close two rooms may sit.
    STEP = 62
    CLEARANCE = 54

    module_function

    # dungeon: a rolled (and provenanced) dungeon. Returns a new one; the
    # argument is left alone.
    def apply(dungeon, level:, seed:, encounters: [], tables: {})
      level = level.to_i.clamp(0, MAX_LEVEL)
      return dungeon if level.zero? || dungeon["kind"] != "dungeon"

      rooms = Overrides.deep_dup(dungeon["rooms"])
      paths = Overrides.deep_dup(dungeon["paths"])
      core = rooms.map { |room| room["key"] }
      pool = Pool.new(Battle::Rng.new(Battle::Rng.seed_state(Integer(seed) ^ SALT)))
      # The core's own deepest column, so no core room shifts when the dial moves.
      max_depth = [ rooms.filter_map { |room| room["depth"] }.max.to_i, 1 ].max

      (level * PER_LEVEL).times do |i|
        break unless grow(pool, rooms, paths, core, i + 1, max_depth, encounters, tables)
      end

      dungeon.merge("rooms" => rooms, "paths" => paths)
    end

    # One extra room, appended to `rooms` and `paths`. nil when there is
    # nowhere left to put one, which ends the growing.
    def grow(pool, rooms, paths, core, number, max_depth, encounters, tables)
      shape = pool.choose(SHAPES)
      anchor, second = anchors(pool, rooms, paths, core, shape)
      return nil unless anchor

      key = "elab-#{number}"
      room = { "key" => key, "name" => name(pool, tables, number),
               "depth" => [ anchor, second ].compact.map { |room| room["depth"].to_i }.min + 1,
               "decision" => decision(pool, encounters, tables), "elaborated" => true }
      place(room, rooms, anchor, max_depth)
      rooms << room
      paths << { "key" => "path-#{key}", "from" => anchor["key"], "to" => key, "elaborated" => true }
      paths << { "key" => "path-#{key}-b", "from" => key, "to" => second["key"], "elaborated" => true } if second
      room
    end

    # Where it hangs. An alcove and a chain take one room; a parallel passage
    # takes two that are ALREADY joined, which is the whole reason it can't
    # become a shortcut. A chain prefers an earlier extra, so the dial grows
    # outward instead of fanning everything off the core. Always exactly one
    # draw, so the stream keeps its shape whichever branch runs.
    def anchors(pool, rooms, paths, core, shape)
      free = rooms.reject { |room| exits(paths, room["key"]) >= Dungeon::MAX_EXITS }
      return [ nil, nil ] if free.empty?

      if shape == "parallel" && (pairs = joined_pairs(rooms, paths, free)).any?
        return pairs[pool.int(pairs.size)]
      end

      wanted = shape == "chain" ? free.reject { |room| core.include?(room["key"]) } : free
      wanted = free if wanted.empty?
      [ wanted[pool.int(wanted.size)], nil ]
    end

    # Pairs of rooms a path already joins, both with an exit to spare.
    # Plain Ruby, no ActiveSupport: lib/generators is pure and its specs load
    # it without Rails (so no #index_by, #presence or friends in here).
    def joined_pairs(rooms, paths, free)
      by_key = free.to_h { |room| [ room["key"], room ] }
      paths.filter_map do |path|
        a, b = by_key[path["from"]], by_key[path["to"]]
        [ a, b ] if a && b
      end
    end

    def exits(paths, key)
      paths.count { |path| path["from"] == key || path["to"] == key }
    end

    def decision(pool, encounters, tables)
      Dungeon.simple_decision(pool, pool.choose(Dungeon.possible(SPREAD, encounters, tables)), encounters, tables)
    end

    # Named from the world's own room table, falling back to something plain.
    def name(pool, tables, number)
      pool.pick_fresh(tables.fetch("rooms", []))&.fetch("text") || "Side room #{number}"
    end

    # Its depth's column, as Dungeon::layout draws them, then the first free
    # slot above or below its anchor. Deeper than the core means sharing the
    # last column rather than falling off the sheet.
    def place(room, rooms, anchor, max_depth)
      room["x"] = (80 + room["depth"] * (Dungeon::WIDTH - 160) / max_depth).clamp(80, Dungeon::WIDTH - 80)
      taken = rooms.select { |other| (other["x"].to_i - room["x"]).abs < CLEARANCE }.map { |other| other["y"].to_i }
      room["y"] = free_y(anchor["y"].to_i, taken)
    end

    def free_y(from, taken)
      (0..12).each do |ring|
        [ from + ring * STEP, from - ring * STEP ].each do |y|
          next unless y.between?(40, Dungeon::HEIGHT - 40)
          return y if taken.none? { |other| (other - y).abs < CLEARANCE }
        end
      end
      from.clamp(40, Dungeon::HEIGHT - 40)
    end
  end
end
