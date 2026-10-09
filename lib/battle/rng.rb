# frozen_string_literal: true

module Battle
  # Seeded PRNG (mulberry32) whose entire state is one 32-bit integer.
  #
  # Not `Random.new(seed)` (HANDOFF §5): Ruby's Random cannot expose its
  # internal state as plain data. Storing a single integer in the battle
  # state gives the same guarantee — replays are exact — while keeping the
  # state JSON-serialisable and resumable from any point.
  class Rng
    MASK = 0xFFFF_FFFF

    attr_reader :state

    def self.seed_state(seed)
      Integer(seed) & MASK
    end

    def initialize(state)
      @state = Integer(state) & MASK
    end

    def next_u32
      @state = (@state + 0x6D2B79F5) & MASK
      t = @state
      t = imul(t ^ (t >> 15), t | 1)
      t ^= (t + imul(t ^ (t >> 7), t | 61)) & MASK
      (t ^ (t >> 14)) & MASK
    end

    # Uniform integer in 0...n.
    def int(n)
      raise ArgumentError, "n must be positive" unless n.positive?

      (next_u32 * n) >> 32
    end

    # High is good, everywhere: a d100 (1–100) comes in when it reaches what
    # was needed, and what's needed is the top `chance` percent of it (a 70%
    # chance needs 31 or over). The same single draw as #percent?, so the
    # stream is identical; the roll is for showing (the dice on the board).
    def d100(chance)
      roll = int(100) + 1
      [ roll >= Rng.target(chance), roll ]
    end

    # The roll a d100 needs for a percent chance: 101 for none, 1 for certain.
    def self.target(chance)
      (101 - chance).clamp(1, 101)
    end

    # True with the given percent chance. Always draws, so RNG consumption
    # does not depend on the chance value.
    def percent?(chance)
      int(100) < chance
    end

    def pick(array)
      return nil if array.empty?

      array[int(array.size)]
    end

    private

    def imul(a, b)
      (a * b) & MASK
    end
  end
end
