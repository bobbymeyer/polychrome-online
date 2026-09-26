# frozen_string_literal: true

# One expression's image for an NPC or a character (§7: "expression tag
# selects portrait variant"). The expressions are a closed set, like the
# engine's other vocabularies, so every speaker can be asked for any of them.
class Portrait < ApplicationRecord
  EXPRESSIONS = %w[neutral happy sad angry surprised worried determined].freeze

  belongs_to :owner, polymorphic: true
  has_one_attached :image

  validates :expression, inclusion: { in: EXPRESSIONS }, uniqueness: { scope: %i[owner_type owner_id] }
end
