# frozen_string_literal: true

# Turns of phrase the game's lines share, wherever they're said (models and
# helpers both).
module Wording
  # "a Potion", "an Antidote", "an Echo Screen".
  def self.a_or_an(name)
    "#{name.to_s.match?(/\A[aeiou]/i) ? 'an' : 'a'} #{name}"
  end
end
