# frozen_string_literal: true

module Pointcrawl
  # What happens in the world overnight, while the party sleeps: small,
  # local, and by rule, from the campaign's own dice.
  #
  # - Clocks that tick "now and then" go on a segment on a roll.
  # - Rumours travel one road a day from wherever they've reached, and fade
  #   after a while.
  # - Antagonists who got away wander to a place nearby.
  # - Caravans are attacked on dangerous roads between towns, which drives
  #   the prices up at both ends; prices drift back towards normal.
  #
  # Pure: the state and the RNG go in, what happened and the RNG come out,
  # so the same night always goes the same way. The draws are fixed per
  # thing considered, so a new rumour doesn't change where an antagonist
  # goes.
  #
  # world: {
  #   "places"      => [{ "id", "name", "town" => true/false, "settled" => true/false }],
  #   "roads"       => [{ "from", "to", "state" }],                 state: open, dangerous, blocked
  #   "clocks"      => [clock ids that tick now and then],
  #   "rumours"     => [{ "id", "reached" => [place ids], "age" }],
  #   "antagonists" => [{ "id", "name", "at" => place id or nil }],
  #   "prices"      => { place id => percent shift }
  # }
  module Overnight
    CLOCK_CHANCE = 35      # percent, for a clock that ticks now and then
    RUMOUR_LIFE = 6        # days a rumour keeps travelling
    WANDER_CHANCE = 50     # percent, for an antagonist at large
    CARAVAN_CHANCE = 15    # percent, per dangerous road between two towns
    CARAVAN_SHOCK = 15     # percent on prices, at each end
    PRICE_CAP = 50
    PRICE_EASE = 5         # percent back towards normal each day

    module_function

    # Returns [new_rng_state, happenings]:
    #   { "kind" => "clock", "clock" }
    #   { "kind" => "spread", "rumour", "to" => [place ids] }
    #   { "kind" => "fade", "rumour" }
    #   { "kind" => "moved", "npc", "name", "from", "to" }
    #   { "kind" => "caravan", "from", "to" }
    #   { "kind" => "price", "place", "shift" }
    def run(world, rng_state)
      rng = Battle::Rng.new(rng_state)
      roads = passable(world.fetch("roads", []))
      happenings = []

      world.fetch("clocks", []).each do |clock|
        happenings << { "kind" => "clock", "clock" => clock } if rng.percent?(CLOCK_CHANCE)
      end

      world.fetch("rumours", []).each do |rumour|
        if rumour["age"].to_i >= RUMOUR_LIFE
          happenings << { "kind" => "fade", "rumour" => rumour["id"] }
          next
        end
        reached = rumour["reached"]
        onward = reached.flat_map { |place| neighbours(roads, place) }.uniq - reached
        happenings << { "kind" => "spread", "rumour" => rumour["id"], "to" => onward.sort } if onward.any?
      end

      places = world.fetch("places", []).to_h { |p| [ p["id"], p ] }
      world.fetch("antagonists", []).each do |npc|
        go = rng.percent?(WANDER_CHANCE)
        choices = npc["at"] ? settled_nearby(roads, places, npc["at"]) : []
        pick = choices.empty? ? rng.int(1) : rng.int(choices.size)
        next unless go && choices.any?

        happenings << { "kind" => "moved", "npc" => npc["id"], "name" => npc["name"], "from" => npc["at"], "to" => choices[pick] }
      end

      prices = world.fetch("prices", {}).transform_keys(&:to_i)
      shocked = Hash.new(0)
      roads.select { |road| road["state"] == "dangerous" }.sort_by { |road| [ road["from"], road["to"] ] }.each do |road|
        ends = [ road["from"], road["to"] ]
        next rng.int(1) unless ends.all? { |id| places.dig(id, "town") }
        next unless rng.percent?(CARAVAN_CHANCE)

        happenings << { "kind" => "caravan", "from" => road["from"], "to" => road["to"] }
        ends.each { |id| shocked[id] += CARAVAN_SHOCK }
      end

      (prices.keys | shocked.keys).sort.each do |id|
        was = prices.fetch(id, 0)
        eased = was.positive? ? [ was - PRICE_EASE, 0 ].max : [ was + PRICE_EASE, 0 ].min
        now = (eased + shocked[id]).clamp(-PRICE_CAP, PRICE_CAP)
        happenings << { "kind" => "price", "place" => id, "shift" => now } if now != was
      end

      [ rng.state, happenings ]
    end

    def passable(roads)
      roads.reject { |road| road["state"] == "blocked" }
    end

    def neighbours(roads, place)
      roads.filter_map { |road| (road["to"] if road["from"] == place) || (road["from"] if road["to"] == place) }
    end

    # Towns and dungeons one road away, and those just past a crossroads or
    # a marsh on the way.
    def settled_nearby(roads, places, from)
      near = neighbours(roads, from)
      beyond = near.reject { |id| places.dig(id, "settled") }.flat_map { |id| neighbours(roads, id) }
      (near + beyond).uniq.select { |id| id != from && places.dig(id, "settled") }.sort
    end
  end
end
