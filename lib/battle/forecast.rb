# frozen_string_literal: true

module Battle
  # How a fight is likely to go, for the GM setting it up: the same battle
  # played out several times from different seeds, by a sensible party:
  # anyone who can raise the fallen or mend the badly hurt does, and
  # everyone else attacks (each round then times out, so the rest repeat
  # their last command or Attack). Players who cast, buff and use items do
  # better, so this is a floor, not a prediction. Pure: states in, a summary
  # out.
  module Forecast
    MAX_ROUNDS = 40

    module_function

    # states: initial battle states (one per seed). Returns
    # { "runs", "wins", "rounds" (average), "hp_left" (average percent of
    # the party's max HP still standing at the end), "downed" (average
    # characters down) }.
    def run(states)
      results = states.map { |state| play(state) }
      return { "runs" => 0 } if results.empty?

      {
        "runs" => results.size,
        "wins" => results.count { |r| r[:result] == "victory" },
        "rounds" => (results.sum { |r| r[:rounds] }.to_f / results.size).round(1),
        "hp_left" => results.sum { |r| r[:hp_left] } / results.size,
        "downed" => (results.sum { |r| r[:downed] }.to_f / results.size).round(1)
      }
    end

    # Below this share of their HP, an ally gets mended.
    HURT = 40

    def play(state)
      rounds = 0
      while state["status"] == "input" && rounds < MAX_ROUNDS
        State.awaiting_input(state).each do |id|
          command = sensible(state, id) or next
          begin
            state, = Resolver.apply(state, { "type" => "command", "actor" => id, "command" => command })
          rescue InvalidAction
            next # not after all (silenced, say): the timeout's default stands
          end
        end
        state, = Resolver.apply(state, { "type" => "timeout" }) if state["status"] == "input"
        rounds += 1
      end
      party = state["units"].select { |u| u["side"] == "party" && !u["guest"] }
      max = party.sum { |u| u["stats"]["max_hp"] }
      {
        result: state["status"], rounds: rounds,
        hp_left: max.zero? ? 0 : party.sum { |u| u["hp"] } * 100 / max,
        downed: party.count { |u| u["hp"].zero? }
      }
    end

    # What a sensible player does this round, if it isn't just attacking:
    # raise the fallen, or mend whoever is badly hurt.
    def sensible(state, id)
      unit = state["units"].find { |u| u["id"] == id }
      allies = state["units"].select { |u| u["side"] == unit["side"] && !u["gone"] }
      fallen = allies.find { |u| u["hp"].zero? }
      hurt = allies.select { |u| u["hp"].positive? && u["hp"] * 100 < u["stats"]["max_hp"] * HURT }.min_by { |u| u["hp"] }
      known = unit["abilities"].filter_map { |a| state["abilities"][a] }.select { |a| State.usable?(unit, a) }
      if fallen && (raise_it = known.find { |a| State.revives?(a) && a["target"] == "single_ally" })
        { "kind" => "ability", "ability" => raise_it["id"], "target" => fallen["id"] }
      elsif hurt && (mend = known.find { |a| State.heals?(a) && %w[single_ally all_allies].include?(a["target"]) })
        { "kind" => "ability", "ability" => mend["id"], "target" => (hurt["id"] if mend["target"] == "single_ally") }.compact
      end
    end
  end
end
