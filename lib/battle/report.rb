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
  #   #      "units" => [ { "id", "name", "kind", "kind_name", "side", "dealt",
  #   #                     "taken", "healed", "kos", "downed", "actions",
  #   #                     "abilities" => { "Fire" => 2 }, "misses", "crits",
  #   #                     "mp_spent", "hp", "max_hp" } ],
  #   #      "moves" => [ { "side", "name", "uses", "dealt", "healed" } ],
  #   #      "by_round" => [ { "round" => 1, "party" => 24, "enemy" => 16 } ],
  #   #      "by_status" => { "poison" => 9 }, "sides" => { "party" => {...}, "enemy" => {...} } }
  module Report
    # What a side's rows add up to.
    TOTALS = %w[dealt taken healed kos downed actions misses crits mp_spent].freeze
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
      using = {} # unit => the move it's making this turn (or its counter)
      moves = Hash.new { |all, (on, name)| all[[ on, name ]] = { "side" => on, "name" => name, "uses" => 0, "dealt" => 0, "healed" => 0 } }

      events.each do |event|
        case event["type"]
        when "round_start"
          round = event["round"]
          played += 1
        when "turn_start"
          turns += 1
          actor = event["unit"]
        when "turn_end"
          actor = nil
          using = {}
        when *ACTIONS
          actor = event["actor"]
          next unless (acting = rows[actor])

          acting["mp_spent"] += event["mp_cost"].to_i
          used = case event["type"]
          when "item_used" then event["name"]
          when "counter" then "Counter"
          else names.fetch(event["ability"], event["ability"])
          end
          next unless used

          using[actor] = used
          moves[[ side[actor], used ]]["uses"] += 1
          next if event["type"] == "counter" # a reaction, not one of its actions

          acting["actions"] += 1
          acting["abilities"][used] += 1
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
            moves[[ side[source], using[source] ]]["dealt"] += landed if rows[source] && using[source]
            by_round[round][side[source]] += landed if %w[party enemy].include?(side[source])
            last_hit[target] = source
          end
        when "heal"
          target = event["target"]
          landed = event["hp"] - hp.fetch(target, event["hp"])
          hp[target] = event["hp"]
          source = event["actor"] || actor
          if rows[source] && landed.positive?
            rows[source]["healed"] += landed
            moves[[ side[source], using[source] ]]["healed"] += landed if using[source]
          end
        when "revive"
          hp[event["target"]] = event["hp"] if event.key?("hp")
        when "ko"
          killer = last_hit[event["target"]]
          rows[killer]["kos"] += 1 if rows[killer] && side[killer] != side[event["target"]]
          rows[event["target"]]["downed"] += 1 if rows[event["target"]]
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
        "moves" => moves.values.sort_by { |move| [ move["side"] == "party" ? 0 : 1, -move["uses"], move["name"].to_s ] },
        "sides" => %w[party enemy].to_h { |name| [ name, totals(units.select { |row| row["side"] == name }) ] }
      }
    end

    # Many battles' reports together, for seeing what a campaign's fights
    # come to: each battle in a line, each kind of fighter and each move
    # over every battle it was in. entries: [{ "battle" => { "id", "name", ... },
    # "report" => build(...) }], newest first or however they're to be listed.
    #
    #   # => { "battles" => [ { ..., "result", "rounds", "party_dealt", ... } ],
    #   #      "results" => { "victory" => 3, "defeat" => 1 },
    #   #      "fighters" => [ { "side", "kind", "name", "battles", "units", "dealt",
    #   #                        ..., "dealt_per_battle", "dealt_per_action" } ],
    #   #      "moves" => [ { "side", "name", "uses", "dealt", "healed", "dealt_per_use" } ] }
    def across(entries)
      fighters = {}
      moves = {}
      battles = entries.map do |entry|
        report = entry["report"]
        report["units"].group_by { |unit| [ unit["side"], unit["kind"] ] }.each do |(side, kind), units|
          fighter = fighters[[ side, kind ]] ||= { "side" => side, "kind" => kind, "name" => units.first["kind_name"], "battles" => 0, "units" => 0 }
                                                 .merge(TOTALS.to_h { |key| [ key, 0 ] })
          fighter["battles"] += 1
          fighter["units"] += units.size
          TOTALS.each { |key| fighter[key] += units.sum { |unit| unit[key] } }
        end
        report.fetch("moves", []).each do |move|
          total = moves[[ move["side"], move["name"] ]] ||= { "side" => move["side"], "name" => move["name"], "uses" => 0, "dealt" => 0, "healed" => 0 }
          %w[uses dealt healed].each { |key| total[key] += move[key] }
        end
        party, enemy = report["sides"].values_at("party", "enemy")
        entry["battle"].merge("result" => report["result"], "rounds" => report["rounds"], "turns" => report["turns"],
                              "party_dealt" => party["dealt"], "party_taken" => party["taken"], "party_healed" => party["healed"],
                              "party_downed" => party["downed"], "enemies_downed" => enemy["downed"],
                              "foes" => report["units"].select { |unit| unit["side"] == "enemy" }.map { |unit| unit["kind_name"] }.tally)
      end

      fighters.each_value do |fighter|
        fighter["dealt_per_battle"] = per(fighter["dealt"], fighter["battles"])
        fighter["dealt_per_action"] = per(fighter["dealt"], fighter["actions"])
      end
      moves.each_value { |move| move["dealt_per_use"] = per(move["dealt"], move["uses"]) }

      {
        "battles" => battles,
        "results" => battles.map { |battle| battle["result"] }.tally,
        "fighters" => fighters.values.sort_by { |f| [ f["side"] == "party" ? 0 : 1, -f["dealt"], f["name"].to_s ] },
        "moves" => moves.values.sort_by { |m| [ m["side"] == "party" ? 0 : 1, -m["uses"], m["name"].to_s ] }
      }
    end

    # An average to one place, or nil when there's nothing to divide by.
    def per(total, count) = (count.zero? ? nil : (total.to_f / count).round(1))

    def row(unit)
      kind, kind_name = kind_of(unit)
      { "id" => unit["id"], "name" => unit["name"], "kind" => kind, "kind_name" => kind_name, "side" => unit["side"],
        "max_hp" => unit.dig("stats", "max_hp"), "abilities" => Hash.new(0) }.merge(TOTALS.to_h { |key| [ key, 0 ] })
    end

    # What a unit is, across battles: "goblin_b" (Goblin B) is a "goblin"
    # (Goblin), lettered as the battle set out a group of them
    # (Battle::State.expand_enemies); a character is themselves.
    def kind_of(unit)
      id, name = unit["id"].to_s, unit["name"].to_s
      letter = id[/_([a-z])\z/, 1]
      return [ id, name ] unless letter && name.end_with?(" #{letter.upcase}")

      [ id.delete_suffix("_#{letter}"), name.delete_suffix(" #{letter.upcase}") ]
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
