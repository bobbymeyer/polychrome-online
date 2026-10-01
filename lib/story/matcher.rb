# frozen_string_literal: true

module Story
  # Picks the row that best fits the moment (Ruskin, ch. 25). Rows are plain
  # hashes, as generator tables keep them:
  #
  #   { "text" => "Smoke hangs over {place}.", "when" => "town, night, !smoke_seen",
  #     "sets" => "smoke_seen", "weight" => 1 }
  #
  # Every row whose conditions all hold competes. The most specific wins:
  # the one asking the most of the moment, so a row for "town, night" beats
  # one for "town", and a row that asks nothing is the fallback. Ties go to
  # the seeded RNG, by weight. A row that names one of the table's lines or
  # veils never competes (Words).
  #
  # Rows carry a little grammar (ch. 1, 16): "{key}" says a fact ("{place}",
  # "{home}"), and a row whose fact isn't there doesn't fit, so "{home} is
  # home." only comes up when someone is; "{dry|still|cold}" picks one.
  #
  # Rows rule each other out (ch. 22) through what they remember: one row
  # sets smoke_seen, another asks for !smoke_seen.
  module Matcher
    SLOT = /\{([^{}]+)\}/

    module_function

    # [next rng state, the chosen line or nil]. The line is
    # { "text" (said), "sets" ([{ "key", "op", "value" }], for
    # Criteria.written), "score", "row" }.
    def best(rows, facts, rng_state, avoid: [])
      fitting = candidates(rows, facts, avoid: avoid)
      return [ rng_state, nil ] if fitting.empty?

      top = fitting.map { |c| c[:score] }.max
      tied = fitting.select { |c| c[:score] == top }
      rng = Battle::Rng.new(rng_state)
      pool = Generators::Pool.new(rng)
      chosen = tied.first
      if tied.size > 1
        picked = pool.pick(tied.map { |c| c[:row] })
        chosen = tied.find { |c| c[:row].equal?(picked) } || chosen
      end
      text = render(chosen[:row]["text"], facts, pool)
      [ rng.state, { "text" => text, "sets" => chosen[:writes].map { |w| w.to_h.transform_keys(&:to_s) }, "score" => top, "row" => chosen[:row] } ]
    end

    # Every row that fits, with how much it asks of the moment:
    # [{ row:, score:, writes: }].
    def candidates(rows, facts, avoid: [])
      Array(rows).filter_map do |row|
        text = row["text"].to_s
        next if text.strip.empty? || Words.clash(text, avoid)

        conditions, problems = Criteria.parse(row["when"])
        writes, write_problems = Criteria.parse_writes(row["sets"])
        next if problems.any? || write_problems.any?
        next unless conditions.all? { |condition| condition.holds?(facts) }

        said = slots(text)
        next unless said.all? { |key| Criteria.truthy?(facts[key]) || facts[key].is_a?(Integer) }

        { row: row, score: conditions.size + said.size, writes: writes }
      end
    end

    # The facts a row's words say: "{place}" → "place"; "{a|b}" says none.
    def slots(text)
      text.to_s.scan(SLOT).flatten.reject { |slot| slot.include?("|") }.map { |slot| slot.strip.downcase }.uniq
    end

    # What's wrong with a row, for whoever writes it.
    def problems(row)
      Criteria.parse(row["when"]).last + Criteria.parse_writes(row["sets"]).last
    end

    def render(text, facts, pool)
      text.to_s.gsub(SLOT) do
        slot = Regexp.last_match(1)
        if slot.include?("|")
          choices = slot.split("|").map(&:strip)
          choices[pool.int(choices.size)]
        else
          facts[slot.strip.downcase].to_s
        end
      end
    end
  end
end
