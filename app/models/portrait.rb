# frozen_string_literal: true

# One expression's image for an NPC or a character (§7: "expression tag
# selects portrait variant"). The expressions are a closed set, like the
# engine's other vocabularies, so every speaker can be asked for any of them.
class Portrait < ApplicationRecord
  EXPRESSIONS = %w[neutral happy sad angry surprised worried determined].freeze
  OWNER_TYPES = %w[Npc Character].freeze

  belongs_to :owner, polymorphic: true
  has_one_attached :image

  validates :expression, inclusion: { in: EXPRESSIONS }, uniqueness: { scope: %i[owner_type owner_id] }

  # Generated like a book entry's image (§8): the speaker is the subject layer
  # and the expression is one more layer after it.
  include Artwork

  def art_kind = "portrait"
  def art_title = "#{owner.name}'s #{expression} portrait"
  def art_world = owner.art_world
  def art_stream = owner
  def art_filename(seed) = "#{owner.name.parameterize}-#{expression}-#{seed}.png"
  def art_subject_label = owner.name
  def art_subject = owner.art_subject
  def art_subject_loras = owner.art_loras
  def art_subject_model = owner.art_model

  def art_detail
    { label: expression.humanize, prompt: Comfy.config.fetch(:expressions, {})[expression.to_sym] || expression }
  end

  # Other expressions start from the neutral portrait's seed, so the face
  # stays closer to the one already picked.
  def art_seed_hint
    return nil if expression == "neutral"

    owner.portraits.find_by(expression: "neutral")&.image_seed
  end
end
