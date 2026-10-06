# frozen_string_literal: true

module Battle
  # How a fight is likely to go: the same battle played out several times
  # from different seeds, by a sensible party. Pure: states in, a summary
  # out.
  #
  # Tactics: "floor" (the battle form's verdict) has anyone who can raise
  # the fallen or mend the badly hurt do it, and everyone else attack (each
  # round then times out, so the rest repeat their last command or Attack).
  # Players who cast, buff and use items do better, so it's a floor, not a
  # prediction. "full" (the simulator) also spends MP: whoever can, uses
  # their hardest-hitting move on the weakest foe (or on all of them). Still
  # no buffs, statuses or items: a sensible party, not a clever one.
  module Forecast
    MAX_ROUNDS = 40

    module_function

    TACTICS = %w[floor full].freeze

    # states: initial battle states (one per seed). Returns
    # { "runs", "wins", "rounds" (average), "hp_left" and "mp_left" (average
    # percent of the party's max HP and MP still theirs at the end),
    # "downed" (average characters down) }; with report: true, also
    # "report", every run's numbers together (Report.across).
    def run(states, tactics: "floor", report: false)
      results = states.map { |state| play(state, tactics: tactics, log: report) }
      return { "runs" => 0 } if results.empty?

      summary = {
        "runs" => results.size,
        "wins" => results.count { |r| r[:result] == "victory" },
        "rounds" => (results.sum { |r| r[:rounds] }.to_f / results.size).round(1),
        "hp_left" => results.sum { |r| r[:hp_left] } / results.size,
        "mp_left" => results.sum { |r| r[:mp_left] } / results.size,
        "downed" => (results.sum { |r| r[:downed] }.to_f / results.size).round(1)
      }
      return summary unless report

      summary.merge("report" => Report.across(results.each_with_index.map do |r, i|
        { "battle" => { "id" => i + 1, "name" => "Run #{i + 1}", "seed" => r[:initial]["seed"] }, "report" => Report.build(r[:initial], r[:events], r[:final]) }
      end))
    end

    # Below this share of their HP, an ally gets mended.
    HURT = 40

    # One battle played out. log: keep the states and every event, for a
    # report of it.
    def play(state, tactics: "floor", log: false)
      initial = state
      events = []
      rounds = 0
      while state["status"] == "input" && rounds < MAX_ROUNDS
        State.awaiting_input(state).each do |id|
          command = sensible(state, id, tactics: tactics) or next
          begin
            state, happened = Resolver.apply(state, { "type" => "command", "actor" => id, "command" => command })
            events.concat(happened) if log
          rescue InvalidAction
            next # not after all (silenced, say): the timeout's default stands
          end
        end
        if state["status"] == "input"
          state, happened = Resolver.apply(state, { "type" => "timeout" })
          events.concat(happened) if log
        end
        rounds += 1
      end
      party = state["units"].select { |u| u["side"] == "party" && !u["guest"] }
      {
        result: state["status"], rounds: rounds,
        hp_left: share(party, "hp", "max_hp"), mp_left: share(party, "mp", "max_mp"),
        downed: party.count { |u| u["hp"].zero? },
        **(log ? { initial: initial, events: events, final: state } : {})
      }
    end

    # What's left of the party's whole pool, as a percent.
    def share(party, now, max)
      total = party.sum { |u| u["stats"][max].to_i }
      total.zero? ? 0 : party.sum { |u| u[now].to_i } * 100 / total
    end

    # What a sensible player does this round, if it isn't just attacking:
    # raise the fallen, or mend whoever is badly hurt; with full tactics,
    # else their hardest-hitting move.
    def sensible(state, id, tactics: "floor")
      unit = state["units"].find { |u| u["id"] == id }
      allies = state["units"].select { |u| u["side"] == unit["side"] && !u["gone"] }
      fallen = allies.find { |u| u["hp"].zero? }
      hurt = allies.select { |u| u["hp"].positive? && u["hp"] * 100 < u["stats"]["max_hp"] * HURT }.min_by { |u| u["hp"] }
      known = unit["abilities"].filter_map { |a| state["abilities"][a] }.select { |a| State.usable?(unit, a) }
      if fallen && (raise_it = known.find { |a| State.revives?(a) && a["target"] == "single_ally" })
        { "kind" => "ability", "ability" => raise_it["id"], "target" => fallen["id"] }
      elsif hurt && (mend = known.find { |a| State.heals?(a) && %w[single_ally all_allies].include?(a["target"]) })
        { "kind" => "ability", "ability" => mend["id"], "target" => (hurt["id"] if mend["target"] == "single_ally") }.compact
      elsif tactics == "full"
        hardest(state, unit, known)
      end
    end

    # The move that does most to the foes standing (a move on them all
    # counts once for each), at the weakest of them; nil to just attack.
    def hardest(state, unit, known)
      foes = state["units"].select { |u| u["side"] != unit["side"] && u["hp"].positive? && !u["gone"] }
      return if foes.empty?

      ctx = Context.new(state)
      weakest = foes.min_by { |u| u["hp"] }
      scored = known.filter_map do |a|
        next unless %w[single_enemy all_enemies].include?(a["target"])

        amount = expected(ctx, unit, a, weakest)
        [ a, a["target"] == "all_enemies" ? amount * foes.size : amount ] if amount.positive?
      end
      best = scored.max_by(&:last)&.first
      return if best.nil? || best["id"] == "attack"

      { "kind" => "ability", "ability" => best["id"], "target" => (weakest["id"] if best["target"] == "single_enemy") }.compact
    end

    # What a move does to a target, by the resolver's own sums (Effects),
    # before the dice's variance and the type chart: enough to choose by.
    def expected(ctx, unit, ability, target)
      Array(ability["effects"]).sum do |effect|
        hits = (effect["hits"] || 1).to_i
        case effect["primitive"]
        when "physical"
          base = (ctx.stat(unit, "atk", basis: effect["basis"]) + ctx.stat(unit, "str", basis: effect["basis"])) * effect.fetch("power", 100) / 100
          Effects.mitigate(base, ctx.stat(target, "def")) * hits
        when "elemental", "drain"
          Effects.mitigate(Effects.scale_by_mag(ctx, unit, effect.fetch("power"), effect["basis"]), ctx.stat(target, "mdef")) * hits
        else 0
        end
      end
    end
  end
end
