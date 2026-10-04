# frozen_string_literal: true

module Pointcrawl
  # A map's roads as plain data, the way the campaign hands them over:
  #   [{ "from" => id, "to" => id, "state" => "open" | "dangerous" | "blocked" }]
  # Roads go both ways. Who uses them: the overnight step (rumours, wanderers),
  # the nearest town to retreat to or to start talk in, and hooks naming the
  # nearest places.
  module Roads
    module_function

    # The roads that can be walked today: a blocked one can't.
    def passable(roads)
      roads.reject { |road| road["state"] == "blocked" }
    end

    def neighbours(roads, place)
      roads.filter_map { |road| (road["to"] if road["from"] == place) || (road["from"] if road["to"] == place) }
    end

    # The first of `wanted` (ids) reached by road from `from`, counting
    # `from` itself, or nil if none is. Of several as near as each other,
    # the lowest id: the answer never depends on the order of the rows.
    # The way from one place to another by road, as the roads walked in
    # order (each a road hash), the fewest parts of a day ("duration", 1
    # when a road has none) and then the fewest roads; nil when there is
    # none. Blocked roads aren't walked. Ties go to the lower ids, so the
    # answer never depends on the order of the rows.
    def route(roads, from, to)
      return [] if from == to

      open = passable(roads)
      best = { from => [ 0, 0, [] ] } # place => [time, hops, roads so far]
      frontier = [ from ]
      until frontier.empty?
        place = frontier.min_by { |p| best[p].first(2) + [ p ] }
        frontier.delete(place)
        break if place == to

        time, hops, walked = best[place]
        open.select { |road| road["from"] == place || road["to"] == place }.sort_by { |road| road["id"].to_i }.each do |road|
          there = road["from"] == place ? road["to"] : road["from"]
          cost = [ time + road.fetch("duration", 1).to_i, hops + 1 ]
          next if best[there] && (best[there].first(2) <=> cost) <= 0

          best[there] = [ *cost, walked + [ road ] ]
          frontier << there unless frontier.include?(there)
        end
      end
      best[to]&.last
    end

    def nearest(roads, from, wanted)
      wanted = wanted.to_set
      seen = Set[from]
      frontier = [ from ]
      until frontier.empty?
        found = frontier.select { |place| wanted.include?(place) }.min
        return found if found

        frontier = frontier.flat_map { |place| neighbours(roads, place) }.uniq.reject { |place| seen.include?(place) }
        seen.merge(frontier)
      end
      nil
    end
  end
end
