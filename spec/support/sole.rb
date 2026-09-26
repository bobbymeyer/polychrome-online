# frozen_string_literal: true

# Array#sole (as in ActiveSupport): the only element, or fail loudly.
unless Array.method_defined?(:sole)
  class Array
    def sole
      raise "expected exactly one element, got #{size}: #{inspect}" unless size == 1

      first
    end
  end
end
