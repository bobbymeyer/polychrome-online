# frozen_string_literal: true

module Pointcrawl
  # Rolling for an encounter when the party crosses an edge. Pure: the RNG
  # state goes in and comes back out, so a campaign's rolls are as
  # deterministic and GM-proof as a battle's (docs/HANDOFF.md §1).
  module Encounters
    # Percent chance of an encounter per crossing, by edge state.
    CHANCE = { "open" => 25, "dangerous" => 100 }.freeze

    module_function

    # entries: [{ "weight" => 3, "monsters" => { "goblin" => 3 } }, ...]
    # Returns [new_rng_state, monsters_or_nil]. Always draws twice, so the
    # stream never depends on whether the first roll hit.
    def roll(rng_state, entries, edge_state)
      rng = Battle::Rng.new(rng_state)
      hit = rng.percent?(CHANCE.fetch(edge_state, 0))
      pick = weighted(rng, entries)
      [ rng.state, (pick if hit) ]
    end

    def weighted(rng, entries)
      total = entries.sum { |entry| entry["weight"] }
      unless total.positive?
        rng.int(1) # keep the draw count fixed
        return nil
      end

      target = rng.int(total)
      entries.each do |entry|
        return entry["monsters"] if target < entry["weight"]

        target -= entry["weight"]
      end
    end
  end
end
