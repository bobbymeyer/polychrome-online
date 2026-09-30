# frozen_string_literal: true

module Generators
  # Where a generated place and its things came from. A dungeon was once
  # something (the Vell manor, sealed after the fire), so some of its rooms
  # are that thing's rooms, its boss room is its heart, whoever died there
  # waits in it, one room still shows how it fell, and its treasure is what
  # the family lost. A town has a founder, an old rival and a feud still
  # running. A shop's blade was made by someone, and owned by someone.
  #
  # A place's past comes from the world's pocket history (History), written
  # onto the atlas; a place the history never saw rolls its own small one
  # from its seed. Its own random stream, drawn after the place is built, so
  # a room's place and decision never change for it.
  #
  # Pure.
  module Provenance
    module_function

    def derive(seed, salt = 0)
      ((seed.to_i * 2_654_435_761) + 97 + salt) & 0x7FFF_FFFF
    end

    # A place's own small history, when the world's hasn't given it one.
    # lore: the world's (Lore), for this and everything below.
    def past_for(seed:, name:, kind:, given_names: [], family_names: [], lore: Lore.empty)
      history = History.generate(seed: derive(seed), places: [ { "key" => "here", "name" => name, "kind" => kind } ],
                                 given_names: given_names, family_names: family_names, years: 80, lore: lore)
      history["places"]["here"]
    end

    def apply(location, past, seed:, lore: Lore.empty)
      return location unless past.is_a?(Hash) && !past.empty?

      location = Overrides.deep_dup(location)
      location["past"] = past
      dungeon(location, past, Pool.new(Battle::Rng.new(derive(seed, 1))), lore) if location["kind"] == "dungeon"
      location
    end

    def dungeon(location, past, pool, lore)
      rooms = location["rooms"]
      boss = rooms.find { |room| room["key"] == location["boss"] }
      was = lore.fetch("pasts", {})[past["was"]]
      fall = lore.fetch("falls", {})[past.dig("fall", "kind")]
      if was
        names = was["rooms"].dup
        others = rooms.reject { |room| room["key"] == location["entrance"] || room.equal?(boss) }
        pool.sample(others.map { |room| { "room" => room } }, (others.size + 1) / 2).each do |chosen|
          break if names.empty?

          chosen["room"]["name"] = names.delete_at(pool.int(names.size))
        end
        boss["name"] = was["heart"] if boss && was["heart"]
      end
      lost = Array(past["lost"])
      boss["decision"]["who"] = "#{lost.last}, #{fall['dead']}" if boss && fall && fall["dead"] && lost.any?
      events = rooms.select { |room| room.dig("decision", "kind") == "event" }
      events[pool.int(events.size)]["decision"]["text"] = fall["trace"] if fall && fall["trace"] && events.any?
      heirlooms(past, was, pool).zip(rooms.select { |room| room.dig("decision", "kind") == "treasure" }).each do |heirloom, room|
        room["decision"]["heirloom"] = heirloom if room
      end
    end

    # What the family lost there; failing that, something the place kept.
    def heirlooms(past, was, pool)
      lost = Array(past["heirlooms"]).map { |h| h.slice("name", "maker", "trade", "made_for", "ago") }
      return lost if lost.any? || !was || !past["family"] || was["keeps"].empty?

      keeps = was["keeps"]
      [ { "name" => "the #{past['family']} #{keeps[pool.int(keeps.size)]}", "made_for" => past["founder"] }.compact ]
    end

    # Who made the shop's made things, and who had them before. One stream
    # per item, so changing the stock doesn't change the rest's stories.
    def stock(slugs, past, seed:, lore: Lore.empty)
      return {} unless past.is_a?(Hash)

      # Whoever in the town makes things makes the shop's (Lore trades).
      smiths = Array(past["makers"])
      owners = lore.fetch("owners", [])
      families = [ past["family"], past["rival"], past.dig("feud", "with"), past["holder"] ].compact.uniq
      slugs.to_h do |slug|
        pool = Pool.new(Battle::Rng.new(derive(seed, slug.to_s.bytes.each_with_index.sum { |b, i| b * (i + 7) })))
        maker = smiths[pool.int(smiths.size)] if smiths.any? && pool.percent?(70)
        family = families[pool.int(families.size)] if families.any? && pool.percent?(60)
        owner = (owners[pool.int(owners.size)].sub("%s", family) if family && owners.any?)
        [ slug, { "maker" => (maker && "#{maker['name']}, #{maker['trade']}"), "owner" => owner }.compact ]
      end.reject { |_, story| story.empty? }
    end
  end
end
