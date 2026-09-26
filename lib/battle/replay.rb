# frozen_string_literal: true

module Battle
  # Folds a list of actions over an initial state. This is what
  # `battle_actions` + the stored initial state reconstruct, and what the
  # determinism tests check against the live `battle_events` log.
  module Replay
    module_function

    # Returns [final_state, events]. Events carry "step": the index of the
    # action that produced them.
    def run(initial_state, actions)
      log = []
      final = actions.each_with_index.reduce(State.normalize(initial_state)) do |state, (action, step)|
        state, events = Resolver.apply(state, action)
        log.concat(events.map { |e| e.merge("step" => step) })
        state
      end
      [ final, log ]
    end
  end
end
