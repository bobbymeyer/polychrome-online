# frozen_string_literal: true

module Battle
  # A battle's numbers, for the people balancing it: built from the replay
  # log (the resolver's events, in order) and the states either side of it,
  # so it says exactly what happened and nothing the log doesn't. Pure.
  #
  # What lands counts, not what was rolled: damage past a unit's last HP
  # (overkill) and healing past its full HP don't, so the totals are what
  # the fight cost each side. Damage a status deals (poison, doom) is the
  # status's, not anyone's.
  #
  #   Battle::Report.build(initial_state, events, final_state)
  #   # => { "result" => "victory", "rounds" => 5 (played), "turns" => 16,
  #   #      "units" => [ { "id", "name", "side", "dealt", "taken", "healed",
  #   #                     "kos", "actions", "abilities" => { "Fire" => 2 },
  #   #                     "misses", "crits", "mp_spent", "hp", "max_hp" } ],
  #   #      "by_round" => [ { "round" => 1, "party" => 24, "enemy" => 16 } ],
  #   #      "by_status" => { "poison" => 9 }, "sides" => { "party" => {...}, "enemy" => {...} } }
  module Report
    # What a side's rows add up to.
    TOTALS = %w[dealt taken healed kos actions misses crits mp_spent].freeze
    # What a unit does: each opens an action, and what follows is that unit's.
    ACTIONS = %w[attack cast item_used counter].freeze

    module_function

    def build(initial_state, events, final_state)
      units = (initial_state.fetch("units", []) + final_state.fetch("units", [])).uniq { |unit| unit["id"] }
      names = abilities(initial_state, final_state)
      hp = initial_state.fetch("units", []).to_h { |unit| [ unit["id"], unit["hp"] ] }
      rows = units.to_h { |unit| [ unit["id"], row(unit) ] }
      side = units.to_h { |unit| [ unit["id"], unit["side"] ] }
      by_round = Hash.new { |rounds, round| rounds[round] = { "round" => round, "party" => 0, "enemy" => 0 } }
      by_status = Hash.new(0)
      round = initial_state["round"] || 1
      actor = nil
      turns = 0
      played = 0
      last_hit = {}

      events.each do |event|
        case event["type"]
        when "round_start"
          round = event["round"]
          played += 1
        when "turn_start"
          turns += 1
          actor = event["unit"]
        when "turn_end" then actor = nil
        when *ACTIONS
          actor = event["actor"]
          next unless (acting = rows[actor])

          acting["actions"] += 1 unless event["type"] == "counter"
          acting["mp_spent"] += event["mp_cost"].to_i
          used = event["type"] == "item_used" ? event["name"] : names.fetch(event["ability"], event["ability"])
          acting["abilities"][used] += 1 if used
        when "damage"
          target = event["target"]
          landed = [ event["amount"].to_i, hp.fetch(target, event["amount"].to_i) ].min
          hp[target] = event["hp"]
          rows[target]["taken"] += landed if rows[target]
          if (status = event["status"])
            by_status[status] += landed
            last_hit[target] = nil
          else
            source = event["actor"] || actor
            rows[source]["dealt"] += landed if rows[source]
            by_round[round][side[source]] += landed if %w[party enemy].include?(side[source])
            last_hit[target] = source
          end
        when "heal"
          target = event["target"]
          landed = event["hp"] - hp.fetch(target, event["hp"])
          hp[target] = event["hp"]
          source = event["actor"] || actor
          rows[source]["healed"] += landed if rows[source] && landed.positive?
        when "revive"
          hp[event["target"]] = event["hp"] if event.key?("hp")
        when "ko"
          killer = last_hit[event["target"]]
          rows[killer]["kos"] += 1 if rows[killer] && side[killer] != side[event["target"]]
          hp[event["target"]] = 0
        when "miss"
          rows[event["actor"]]["misses"] += 1 if rows[event["actor"]]
        when "crit"
          rows[event["actor"]]["crits"] += 1 if rows[event["actor"]]
        end
      end

      ended = final_state.fetch("units", []).to_h { |unit| [ unit["id"], unit ] }
      rows.each_value do |row|
        last = ended[row["id"]]
        row["hp"] = last ? last["hp"] : hp[row["id"]]
        row["abilities"] = row["abilities"].sort_by { |name, count| [ -count, name.to_s ] }.to_h
      end
      units = rows.values.sort_by { |row| [ row["side"] == "party" ? 0 : 1, row["name"].to_s ] }

      {
        "result" => final_state["status"],
        "rounds" => played, # rounds that were played, not the one waiting for commands
        "turns" => turns,
        "units" => units,
        "by_round" => by_round.values.sort_by { |r| r["round"] },
        "by_status" => by_status,
        "sides" => %w[party enemy].to_h { |name| [ name, totals(units.select { |row| row["side"] == name }) ] }
      }
    end

    def row(unit)
      { "id" => unit["id"], "name" => unit["name"], "side" => unit["side"], "max_hp" => unit.dig("stats", "max_hp"),
        "abilities" => Hash.new(0) }.merge(TOTALS.to_h { |key| [ key, 0 ] })
    end

    def totals(rows)
      TOTALS.to_h { |key| [ key, rows.sum { |row| row[key] } ] }
    end

    # Ability ids to the names the table reads, from the battle's own library.
    def abilities(*states)
      states.flat_map do |state|
        library = state["abilities"]
        pairs = library.is_a?(Hash) ? library.map { |id, ability| [ id, ability ] } : Array(library).map { |ability| [ nil, ability ] }
        pairs.filter_map { |id, ability| [ ability["id"] || id, ability["name"] ] if ability.is_a?(Hash) && ability["name"] }
      end.to_h
    end
  end
end
