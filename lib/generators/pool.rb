# frozen_string_literal: true

module Generators
  # Seeded picks from generator-table entries. Entries are plain hashes with
  # an optional integer "weight" (default 1). Draws come from Battle::Rng, so
  # a location regenerates identically from its seed.
  class Pool
    def initialize(rng)
      @rng = rng
    end

    attr_reader :rng

    def int(n)
      @rng.int(n)
    end

    def between(min, max)
      min + @rng.int(max - min + 1)
    end

    def percent?(chance)
      @rng.percent?(chance)
    end

    # One weighted entry, or nil for an empty pool.
    def pick(entries)
      total = entries.sum { |entry| weight(entry) }
      return nil unless total.positive?

      target = @rng.int(total)
      entries.find { |entry| (target -= weight(entry)).negative? }
    end

    # Like #pick, but prefers rows this pool hasn't handed out yet, so one
    # place doesn't repeat itself until its table runs out. Same number of
    # draws either way.
    def pick_fresh(entries)
      fresh = entries.reject { |entry| used.include?(entry.except("weight")) }
      chosen = pick(fresh.any? { |entry| weight(entry).positive? } ? fresh : entries)
      used << chosen.except("weight") if chosen
      chosen
    end

    # Up to n distinct entries, weighted, without replacement.
    def sample(entries, n)
      remaining = entries.select { |entry| weight(entry).positive? }
      Array.new([ n, remaining.size ].min) { remaining.delete_at(remaining.index(pick(remaining))) }
    end

    # A weighted choice from a { value => weight } hash.
    def choose(weights)
      pick(weights.map { |value, w| { "value" => value, "weight" => w } })&.fetch("value")
    end

    private

    def used
      @used ||= Set.new
    end

    def weight(entry)
      [ entry.fetch("weight", 1).to_i, 0 ].max
    end
  end
end
