# frozen_string_literal: true

# Stand-in for Battle::Rng in formula specs: returns queued draws (as the
# value of #int), falling back to a fixed default when the queue is empty.
# A d100 reads a scripted value the way the specs were written, as how far
# from coming in it is: 0 is the surest roll (100), 99 the worst (1).
class ScriptedRng < Battle::Rng
  attr_reader :draws

  def initialize(*values, default: 0)
    super(0)
    @queue = values
    @default = default
    @draws = 0
  end

  def int(n)
    @draws += 1
    value = @queue.empty? ? [ @default, n - 1 ].min : @queue.shift
    raise ArgumentError, "scripted #{value} out of range 0...#{n}" unless value < n

    value
  end

  def d100(chance)
    roll = 100 - int(100)
    [ roll >= Battle::Rng.target(chance), roll ]
  end
end
