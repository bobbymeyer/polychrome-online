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
