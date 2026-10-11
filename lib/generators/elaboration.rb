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
    # One more way out than the generator's own tree cap. The dial is working
    # around a shape that is already built, so holding it to the generator's
    # limit leaves cramped rolls with nowhere to grow at all.
    MAX_EXITS = Dungeon::MAX_EXITS + 1

    STEP = 62
    CLEARANCE = 54

    module_function

    # dungeon: a rolled (and provenanced) dungeon. Returns a new one; the
    # argument is left alone.
    # variant: what tells two dungeons on the SAME seed apart. Seeded
    # campaigns hand their dungeons identical seeds -- Seeds::JustSeven's
    # chain_seed hunts for the first corridor seed and every one of its
    # templates has the same config, so five of the seven came out on seed 7
    # and elaborated into the same six rooms, in the same order. The seed
    # alone is not enough entropy; the location's own name is.
    def apply(dungeon, level:, seed:, variant: nil, encounters: [], tables: {})
      level = level.to_i.clamp(0, MAX_LEVEL)
      return dungeon if level.zero? || dungeon["kind"] != "dungeon"

      rooms = Overrides.deep_dup(dungeon["rooms"])
      paths = Overrides.deep_dup(dungeon["paths"])
      core = rooms.map { |room| room["key"] }
      pool = Pool.new(Battle::Rng.new(stream_for(seed, variant)))
      # The core's own deepest column, so no core room shifts when the dial moves.
      max_depth = [ rooms.filter_map { |room| room["depth"] }.max.to_i, 1 ].max

      # Nothing the dial adds may sit deeper than the boss: Location's
      # #barred_by holds the party back from anything deeper than a room
      # with a fight still in it, so a room past the boss can only be
      # reached once the boss is dead and the place is finished with. Those
      # rooms would never be played.
      ceiling = rooms.find { |room| room["key"] == dungeon["boss"] }&.fetch("depth").to_i || max_depth

      (level * PER_LEVEL).times do |i|
        break unless grow(pool, rooms, paths, core, i + 1, max_depth, ceiling, encounters, tables)
      end

      dungeon.merge("rooms" => rooms, "paths" => paths)
    end

    # Its own stream, salted away from the dungeon's own roll and stirred by
    # the variant so that two dungeons on one seed are not one dungeon twice.
    def stream_for(seed, variant)
      mixed = Integer(seed) ^ SALT
      variant.to_s.each_byte { |byte| mixed = ((mixed * 31) + byte) & 0xFFFF_FFFF }
      Battle::Rng.seed_state(mixed)
    end

    # One extra room, appended to `rooms` and `paths`. nil when there is
    # nowhere left to put one, which ends the growing.
    def grow(pool, rooms, paths, core, number, max_depth, ceiling, encounters, tables)
      shape = pool.choose(SHAPES)
      anchor, second = anchors(pool, rooms, paths, core, shape, ceiling)
      return nil unless anchor

      key = "elab-#{number}"
      room = { "key" => key, "name" => name(pool, tables, number, rooms.map { |other| other["name"] }),
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
    # outward instead of fanning everything off the core.
    #
    # Weighted by the exits a room has left, not picked flat. Flat picking
    # piles the rooms up at the deep end: a chain prefers an extra, extras
    # hang off whatever came before, and on a corridor that snowballs into
    # the last column while the first rooms get nothing. Favouring the rooms
    # with the most exits free spreads the growth along the whole way down.
    #
    # And never anchor so deep that the new room lands past the boss -- see
    # the ceiling in #apply.
    def anchors(pool, rooms, paths, core, shape, ceiling)
      # Shallow enough that the new room still lands at or above the boss.
      # No fallback to the deeper rooms: when the shallow ones are full the
      # dial stops growing rather than putting a room nobody can walk. So a
      # high level on a cramped dungeon adds fewer rooms than it offers,
      # which is the right way round.
      free = rooms.reject { |room| exits(paths, room["key"]) >= MAX_EXITS || room["depth"].to_i >= ceiling }
      return [ nil, nil ] if free.empty?

      if shape == "parallel" && (pairs = joined_pairs(rooms, paths, free)).any?

        chosen = pool.pick(pairs.map { |a, b| { "pair" => [ a, b ], "weight" => room_weight(paths, a) + room_weight(paths, b) } })
        return chosen["pair"]
      end

      wanted = shape == "chain" ? free.reject { |room| core.include?(room["key"]) } : free
      wanted = free if wanted.empty?
      [ pool.pick(wanted.map { |room| { "room" => room, "weight" => room_weight(paths, room) } })["room"], nil ]
    end

    # Room for one more way in, and then some: a room with every exit but one
    # spare is picked before a room that is nearly full.
    def room_weight(paths, room)
      [ MAX_EXITS - exits(paths, room["key"]), 1 ].max
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

    # Named the way the dungeon's own rooms are (Dungeon.room_name): composed
    # from a part and a quality where the world gives this dungeon both, else
    # from its flat table. `taken` keeps one dungeon from repeating itself.
    def name(pool, tables, number, taken)
      Dungeon.room_name(pool, tables, taken) || "Side room #{number}"
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
