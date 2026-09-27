# frozen_string_literal: true

module Battle
  # How a fight is likely to go, for the GM setting it up: the same battle
  # played out several times from different seeds, with everyone doing the
  # simplest thing (each round times out, so characters repeat their last
  # command or Attack). Real players heal, cast and use items, so this is a
  # floor, not a prediction. Pure: states in, a summary out.
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

    def play(state)
      rounds = 0
      while state["status"] == "input" && rounds < MAX_ROUNDS
        state, = Resolver.apply(state, { "type" => "timeout" })
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
  end
end
