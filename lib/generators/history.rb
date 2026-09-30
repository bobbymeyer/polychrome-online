# frozen_string_literal: true

module Generators
  # A pocket history, run before play: a few families over the places of a
  # region, for a century or so, in five-year steps. Families found towns and
  # build manors and mines, marry, quarrel, feud, betray each other, drown,
  # sell up and flee; places burn, flood and get sealed. Small and local, not
  # epic. What comes out is plain data the canon is written from (World::
  # Chronicle): events for the codex, living heads for the cast, and a past
  # for every place (who founded it, who hates whom, what a dungeon was).
  #
  # places:       [{ "key", "name", "kind" }]   kind: town, dungeon, landmark, wilds
  # given_names:  ["Mira", ...]                 the world's names tables
  # family_names: ["Vell", ...]                 the world's families tables
  # families:     [{ "name", "trade", "seat" }] the GM's own, kept on reroll
  # lore:         the world's lore (Lore): its trades, what dungeons were,
  #               how places fall, what people quarrel over. A world without
  #               some of it has none of that happen.
  #
  # Pure: same seed and inputs, same history. Time is counted in years ago.
  module History
    STEP = 5
    FOUNDING = 30

    module_function

    def was_for(name, lore) = Lore.was_for(name, lore)

    def generate(seed:, places:, given_names: [], family_names: [], families: [], years: 100, lore: Lore.empty)
      Sim.new(Pool.new(Battle::Rng.new(seed)), places: places, given_names: given_names, family_names: family_names,
                                                 families: families, years: years.to_i.clamp(40, 300), lore: lore).run
    end

    # "the Vells", "the Ashes"
    def plural(name)
      name.to_s.match?(/(s|x|z|ch|sh)\z/) ? "#{name}es" : "#{name}s"
    end

    # "38 years ago", "this year"
    def ago(years)
      case years
      when 0 then "this year"
      when 1 then "last year"
      else "#{years} years ago"
      end
    end

    class Sim
      def initialize(pool, places:, given_names:, family_names:, families:, years:, lore:)
        @pool = pool
        @years = years
        @lore = Lore.empty.merge(lore)
        # The world's names; a world without any still has people, just plainly named.
        @given = unique(given_names).then { |names| names.empty? ? %w[Someone] : names }
        @surnames = unique(family_names)
        @places = places.map { |p| { "key" => p["key"].to_s, "name" => p["name"].to_s, "kind" => p["kind"].to_s } }
        @pinned = Array(families).select { |f| f["name"].to_s.strip != "" }
        @events = []
        @heirlooms = []
        @relations = {}
        @used_given = []
      end

      def run
        make_families
        found_places
        (@years - FOUNDING).step(STEP, -STEP) do |now|
          @now = now
          succeed_the_old
          happen if @pool.percent?(80)
        end
        @now = [ STEP, @years ].min
        settle
        result
      end

      private

      attr_reader :pool

      def plural(name) = History.plural(name)

      def unique(names) = Array(names).map { |n| n.to_s.strip }.reject(&:empty?).uniq

      # --- people ----------------------------------------------------------------

      # A name nobody alive has; once the names run out, the dead's come back.
      def given
        fresh = @given - @used_given
        if fresh.empty?
          @used_given = Array(@families).flat_map { |f| [ f["head"], f["heir"] ] }.compact.map { |p| p["name"].split.first }
          fresh = @given - @used_given
          fresh = @given if fresh.empty?
        end
        name = fresh[pool.int(fresh.size)]
        @used_given << name
        name
      end

      def person(family, born)
        { "name" => "#{given} #{family['name']}", "born" => born }
      end

      def living = @families.reject { |f| f["gone"] }

      def age(person) = person["born"] - @now

      # --- setting up --------------------------------------------------------------

      def make_families
        settled = @places.count { |p| %w[town dungeon].include?(p["kind"]) }
        count = [ [ settled + 1, 3 ].max, 6 ].min + pool.int(2)
        count = [ count, @pinned.size ].max
        surnames = @surnames - @pinned.map { |f| f["name"].to_s.strip }
        @families_named = @pinned.map { |f| f["name"].to_s.strip }
        @families = Array.new(count) do |i|
          pin = @pinned[i]
          surnames = @surnames - @families_named if surnames.empty?
          # Out of the world's family names: a house goes by a number.
          name = pin ? pin["name"].to_s.strip : (surnames.empty? ? "House #{i + 1}" : surnames.delete_at(pool.int(surnames.size)))
          @families_named << name
          trades = @lore["trades"].keys
          trade = pin && trades.include?(pin["trade"]) ? pin["trade"] : pick(trades)
          family = { "key" => "family-#{i}", "name" => name, "trade" => trade, "seat" => nil, "standing" => 2 + pool.int(2),
                     "lineage" => [], "grudges" => [], "gone" => nil, "pinned" => !pin.nil? }
          family["pinned_seat"] = pin["seat"].to_s if pin && pin["seat"].to_s != ""
          family
        end
        @now = @years
        @families.each do |family|
          family["head"] = person(family, @years + 20 + pool.int(20))
          family["heir"] = person(family, family["head"]["born"] - 22 - pool.int(10))
          family["lineage"] << { "name" => family["head"]["name"], "from" => @years }
        end
      end

      # Towns are founded, dungeons built, in the first years: each by a family,
      # who take the town as their seat.
      def found_places
        @history = @places.to_h { |p| [ p["key"], p.merge("lost" => [], "heirlooms" => []) ] }
        # A kept family's seat is theirs; the rest found the other places in turn.
        @families.each { |f| f["seat"] = f["pinned_seat"] if f["pinned_seat"] && @history[f["pinned_seat"]] }
        order = @families.reject { |f| f["seat"] }
        order = @families if order.empty?
        settled = @places.select { |p| %w[town dungeon].include?(p["kind"]) }
        settled.each_with_index.sort_by { |p, i| [ p["kind"] == "town" ? 0 : 1, i ] }.map(&:first).each_with_index do |place, i|
          @now = @years - pool.int(FOUNDING)
          family = @families.find { |f| f["pinned_seat"] == place["key"] } || order[i % order.size]
          past = @history[place["key"]]
          past.merge!("founded" => @now, "founder" => family["head"]["name"], "family" => family["key"], "holder" => family["key"])
          if place["kind"] == "town"
            family["seat"] ||= place["key"]
            record("founded", "#{family['head']['name']} founded #{place['name']}.", places: [ place ], families: [ family ])
          else
            rolled = pick(@lore["pasts"].keys)
            past["was"] = History.was_for(place["name"], @lore) || rolled
            was = past["was"] ? ", #{past['was'].match?(/\A[aeiou]/) ? 'an' : 'a'} #{past['was']}" : ""
            record("built", "The #{plural(family['name'])} built #{place['name']}#{was}.", places: [ place ], families: [ family ])
          end
        end
        @now = @years - FOUNDING
      end

      # --- each step ---------------------------------------------------------------

      def succeed_the_old
        living.each do |family|
          next unless age(family["head"]) > 55 + pool.int(20)

          die(family, family["head"], "old age")
        end
      end

      # Someone dies. The heir takes the house, and a new heir is born; a
      # house with no heir left dies out.
      def die(family, who, fate, place: nil)
        if who.equal?(family["head"])
          family["lineage"].last.merge!("to" => @now, "fate" => fate)
          heir = family["heir"] || person(family, @now + 18 + pool.int(15))
          family["head"] = heir
          family["heir"] = person(family, [ heir["born"] - 20 - pool.int(10), @now + 1 ].max)
          family["lineage"] << { "name" => heir["name"], "from" => @now }
        else
          family["heir"] = person(family, [ family["head"]["born"] - 25 - pool.int(10), @now + 1 ].max)
        end
        @history[place["key"]]["lost"] << who["name"] if place
      end

      KINDS = %w[married quarrel betrayal disaster drowned sold made fled prospered].freeze

      # What a trade makes, when it makes something to be remembered.
      def makes(trade) = @lore["trades"].fetch(trade.to_s, [])

      def makers = living.select { |f| makes(f["trade"]).any? }

      def happen
        weights = {
          "married" => matches.any? ? 3 : 0,
          "quarrel" => pairs.any? && @lore["quarrels"].any? ? 4 : 0,
          "betrayal" => feuds.any? && @lore["betrayals"].any? ? 3 : 0,
          "disaster" => standing_places.any? && @lore["falls"].any? ? 2 : 0,
          "drowned" => waters.any? || @lore["waters"].any? ? 1 : 0,
          "sold" => sellers.any? ? 1 : 0,
          "made" => makers.any? ? 2 : 0,
          "fled" => living.size > 3 && living.any? { |f| f["standing"] <= 1 } ? 2 : 0,
          "prospered" => 1
        }
        send(:"#{pool.choose(weights)}!")
      end

      def pairs = living.combination(2).to_a

      def relation(a, b)
        @relations[[ a["key"], b["key"] ].sort.join("|")] ||= { "score" => 0, "feud" => nil }
      end

      def feuds = pairs.select { |a, b| relation(a, b)["feud"] }

      # Heirs not yet married, of houses on speaking terms (or in a feud one
      # side would like to end).
      def matches
        pairs.select { |a, b| relation(a, b)["score"] >= -3 && !a["heir"]["wed"] && !b["heir"]["wed"] }
      end

      def married!
        a, b = pick(matches)
        a, b = b, a if pool.percent?(50)
        rel = relation(a, b)
        rel["score"] += 2
        ended = rel["feud"] && pool.percent?(50)
        a["heir"]["wed"] = b["heir"]["wed"] = true
        text = "#{a['heir']['name']} married #{b['heir']['name'].split.first} of the #{plural(b['name'])}"
        rel["feud"] = nil if ended
        record("married", "#{text}#{', and the feud was put by' if ended}.", families: [ a, b ])
      end

      def quarrel!
        a, b = pick(pairs)
        rel = relation(a, b)
        rel["score"] -= 2 + pool.int(2)
        cause = pick(@lore["quarrels"])
        if rel["score"] <= -3 && !rel["feud"]
          rel["feud"] = { "since" => @now, "cause" => cause }
          record("feud", "The #{plural(a['name'])} and the #{plural(b['name'])} fell out over #{cause}. It became a feud.", families: [ a, b ])
        else
          record("quarrel", "The #{plural(a['name'])} and the #{plural(b['name'])} quarrelled over #{cause}.", families: [ a, b ])
        end
      end

      # Done in a feud, and not known for what it was: the table hears what
      # happened; the GM knows who did it.
      def betrayal!
        a, b = pick(feuds)
        a, b = b, a if pool.percent?(50)
        how = pick(@lore["betrayals"])
        relation(a, b)["score"] -= 3
        b["standing"] = [ b["standing"] - 1, 0 ].max
        a["standing"] += 1
        b["grudges"] << { "against" => a["key"], "why" => "the time they #{how}", "ago" => @now }
        record("betrayal", "The #{plural(b['name'])} lost their standing; nobody could say how.", families: [ a, b ],
               truth: "#{a['head']['name']} #{how}.")
      end

      def standing_places = @history.values.select { |p| %w[town dungeon].include?(p["kind"]) && !p["fall"] && p["founded"] }

      # A fire, a flood, a sickness. A dungeon falls for good (and someone
      # dies in it, and something is lost there); a town recovers.
      def disaster!
        place = pick(standing_places)
        kind = pick(@lore["falls"].keys)
        if place["kind"] == "town"
          # Only what can strike a town (a fall with a town line), and a
          # town's troubles don't come twice: another fire is a quiet year.
          left = @lore["falls"].select { |_, fall| fall["town"] }.keys - place.fetch("troubles", [])
          chosen = pick(left)
          return prospered! unless chosen

          kind = chosen
          place["troubles"] = place.fetch("troubles", []) + [ kind ]
        end
        holder = family(place["holder"])
        if place["kind"] == "dungeon"
          fall!(place, kind, holder)
        else
          seated = living.select { |f| f["seat"] == place["key"] }
          seated.each { |f| f["standing"] = [ f["standing"] - 1, 0 ].max }
          what = @lore["falls"][kind]["town"].sub("%s", place["name"])
          suspect = feud_enemy(holder)
          record(kind, "#{what}.", places: [ place ], families: seated,
                 truth: (("#{suspect['head']['name']} set it, to hurt the #{plural(holder['name'])}." if suspect && kind == "fire" && pool.percent?(40))))
        end
      end

      def fall!(place, kind, holder)
        fall = @lore["falls"].fetch(kind)
        victim = holder && !holder["gone"] ? (holder["heir"] || holder["head"]) : nil
        suspect = holder && feud_enemy(holder)
        blamed = suspect && pool.percent?(40)
        place["fall"] = { "kind" => kind, "ago" => @now }
        if victim
          die(holder, victim, kind, place: place)
          holder["standing"] = [ holder["standing"] - 1, 0 ].max
        end
        lost = holder && @heirlooms.find { |h| h["family"] == holder["key"] && !h["lost_at"] }
        if lost
          lost["lost_at"] = place["key"]
          place["heirlooms"] << lost["key"]
        end
        text = "#{place['name']} #{fall['did'] || 'fell'}"
        text += ", and #{victim['name']} with it" if victim
        text += "; #{lost['name']} was never found" if lost
        record(kind, "#{text}.#{" It was #{fall['sealed']}." if fall['sealed']}", places: [ place ], families: [ holder ].compact,
               truth: ("#{suspect['head']['name']} had a hand in it." if blamed))
        holder["grudges"] << { "against" => suspect["key"], "why" => "what happened at #{place['name']}", "ago" => @now } if blamed
      end

      def feud_enemy(family)
        return nil unless family

        living.find { |other| other != family && relation(family, other)["feud"] }
      end

      def waters = @places.select { |p| %w[wilds landmark].include?(p["kind"]) }

      # A drowning. In a feud, folk say the other side did it, true or not.
      def drowned!
        family = pick(living)
        who = pool.percent?(70) && family["heir"] ? family["heir"] : family["head"]
        water = pick(waters)
        where = water ? water["name"] : pick(@lore["waters"])
        enemy = feud_enemy(family)
        rumour = enemy && pool.percent?(70)
        true_rumour = rumour && pool.percent?(40)
        die(family, who, "drowned")
        text = "#{who['name']} drowned in #{where}."
        text += " Folk say a #{enemy['name']} held them under." if rumour
        family["grudges"] << { "against" => enemy["key"], "why" => "#{who['name']}'s drowning", "ago" => @now } if rumour
        truth = if true_rumour then "#{enemy['head']['name']} did it."
        elsif rumour then "It was an accident. The #{plural(enemy['name'])} have never known what they're blamed for."
        end
        record("drowned", text, places: [ water ].compact, families: [ family, enemy ].compact, truth: truth)
      end

      def sellers = living.select { |f| f["standing"] <= 2 && @history.values.any? { |p| p["holder"] == f["key"] && p["kind"] == "dungeon" && !p["fall"] } }

      def sold!
        seller = pick(sellers)
        place = pick(@history.values.select { |p| p["holder"] == seller["key"] && p["kind"] == "dungeon" && !p["fall"] })
        buyer = pick(living - [ seller ])
        return prospered! unless buyer

        place["holder"] = buyer["key"]
        relation(seller, buyer)["score"] -= 1
        buyer["standing"] += 1
        record("sold", "The #{plural(seller['name'])} sold #{place['name']} to the #{plural(buyer['name'])}.", places: [ place ], families: [ seller, buyer ])
      end

      # Something made to be remembered: a smith's blade for the head of
      # another house. It turns up later as treasure, with its story.
      def made!
        maker = pick(makers)
        patron = pick(living - [ maker ]) || maker
        things = makes(maker["trade"])
        thing = things[pool.int(things.size)]
        heirloom = { "key" => "heirloom-#{@heirlooms.size}", "name" => "the #{patron['name']} #{thing}", "thing" => thing,
                     "maker" => maker["head"]["name"], "trade" => maker["trade"], "made_for" => patron["head"]["name"],
                     "family" => patron["key"], "ago" => @now }
        @heirlooms << heirloom
        relation(maker, patron)["score"] += 1 unless maker == patron
        record("made", "#{maker['head']['name']}, #{maker['trade']}, made #{heirloom['name']} for #{patron['head']['name']}.",
               families: [ maker, patron ].uniq)
      end

      def fled!
        family = pick(living.select { |f| f["standing"] <= 1 })
        family["gone"] = @now
        family["lineage"].last["to"] = @now
        family["lineage"].last["fate"] = "fled"
        why = family["grudges"].last ? " after #{family['grudges'].last['why']}" : ""
        @history.values.select { |p| p["holder"] == family["key"] && p["kind"] == "dungeon" && !p["fall"] }.each do |place|
          place["fall"] = { "kind" => "abandoned", "ago" => @now }
        end
        record("fled", "The #{plural(family['name'])} left the region#{why}. Their house stands empty.", families: [ family ])
      end

      def prospered!
        family = pick(living)
        family["standing"] += 1
        fortune = pick(@lore["fortunes"])
        record("prospered", "The #{plural(family['name'])} did well#{": #{fortune}" if fortune}.", families: [ family ])
      end

      # Before the present: every dungeon has fallen by now, and somewhere a
      # feud is still running.
      def settle
        standing_places.select { |p| p["kind"] == "dungeon" }.each do |place|
          @now = STEP * (1 + pool.int(4))
          kind = pick(@lore["falls"].keys) or break # a world where nothing falls
          fall!(place, kind, family(place["holder"]))
        end
        @now = STEP
        return if feuds.any? || pairs.empty? || @lore["quarrels"].empty?

        a, b = pairs.min_by { |x, y| [ relation(x, y)["score"], x["key"], y["key"] ] }
        cause = pick(@lore["quarrels"])
        relation(a, b)["score"] = [ relation(a, b)["score"], -3 ].min
        relation(a, b)["feud"] = { "since" => @now, "cause" => cause }
        record("feud", "The #{plural(a['name'])} and the #{plural(b['name'])} fell out over #{cause}. It became a feud.", families: [ a, b ])
      end

      # --- output ------------------------------------------------------------------

      def pick(list)
        list = Array(list)
        list.empty? ? nil : list[pool.int(list.size)]
      end

      def family(key) = @families.find { |f| f["key"] == key }

      def record(kind, text, places: [], families: [], truth: nil)
        @events << { "ago" => @now, "kind" => kind, "text" => text, "places" => places.map { |p| p["key"] },
                     "families" => families.map { |f| f["key"] }, "truth" => truth }.compact
      end

      def result
        {
          "years" => @years,
          "families" => @families.map { |f| family_result(f) },
          "events" => @events.each_with_index.sort_by { |e, i| [ -e["ago"], i ] }.map(&:first),
          "places" => @history.transform_values { |p| place_result(p) },
          "heirlooms" => @heirlooms,
          "feuds" => feuds.map do |a, b|
            feud = relation(a, b)["feud"]
            { "families" => [ a["key"], b["key"] ], "names" => [ a["name"], b["name"] ], "since" => feud["since"], "cause" => feud["cause"] }
          end
        }
      end

      def family_result(f)
        f.slice("key", "name", "trade", "seat", "standing", "lineage", "grudges", "gone", "pinned")
         .merge("head" => (f["head"]["name"] unless f["gone"]), "heir" => (f["heir"]&.dig("name") unless f["gone"])).compact
      end

      def place_result(p)
        founders = family(p["family"])
        holder = family(p["holder"])
        rival = founders && (@families - [ founders ]).min_by { |o| [ relation(founders, o)["score"], o["key"] ] }
        feud = founders && living.find { |o| o != founders && relation(founders, o)["feud"] }
        makers = self.makers.select { |f| f["seat"] == p["key"] }.map { |f| { "name" => f["head"]["name"], "trade" => f["trade"] } }
        out = p.slice("key", "name", "kind", "founded", "founder", "was", "fall", "lost", "heirlooms")
        out["family"] = founders["name"] if founders
        out["founders_left"] = founders["gone"] if founders && founders["gone"]
        out["holder"] = holder["name"] if holder
        out["rival"] = rival["name"] if rival
        out["feud"] = { "with" => feud["name"], "cause" => relation(founders, feud)["feud"]["cause"] } if feud
        out["makers"] = makers if makers.any?
        out["heirlooms"] = @heirlooms.select { |h| h["lost_at"] == p["key"] }
        out.delete("heirlooms") if out["heirlooms"].empty?
        out.delete("lost") if out["lost"].empty?
        out.compact
      end
    end
  end
end
