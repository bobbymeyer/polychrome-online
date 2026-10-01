# frozen_string_literal: true

# Something drawn as a lettered plate until it has art: a creature, a job,
# a character or an NPC. Its colour comes from its name unless one is chosen.
module Colourable
  extend ActiveSupport::Concern

  included do
    normalizes :colour, with: ->(value) { value.presence }
    validates :colour, inclusion: { in: Palette.names, message: ->(*) { "must be one of the stage's colours: #{Palette.names.join(', ')}" } }, allow_nil: true
  end
end
