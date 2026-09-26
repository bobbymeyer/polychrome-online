# frozen_string_literal: true

# Stand-in for Battle::Rng in formula specs: returns queued draws (as the
# value of #int), falling back to a fixed default when the queue is empty.
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
end
