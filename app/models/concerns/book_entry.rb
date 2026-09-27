# frozen_string_literal: true

# Shared by every book entry (§4, §7 "Books"): belongs to a world, is
# addressed by an immutable slug, and has an image slot plus a variant
# recipe (§3.3).
#
# The slug is the entry's identity inside its world. It is what the engine
# sees as an ability/monster id and what AI scripts and drop tables use to
# cross-reference, so it cannot change after creation.
module BookEntry
  extend ActiveSupport::Concern

  SLUG_FORMAT = /\A[a-z][a-z0-9_]*\z/

  included do
    belongs_to :world
    has_one_attached :image

    attr_readonly :slug

    before_validation :default_slug, on: :create

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: { scope: :world_id },
                     format: { with: SLUG_FORMAT, message: "must be lowercase letters, digits and underscores" }
    validate :variant_is_a_recipe

    scope :alphabetical, -> { order(:name) }
  end

  def to_param
    slug_in_database || slug
  end

  # The damage types this entry may name: its world's (World#type_chart).
  def world_types
    world ? world.type_chart.slugs : Battle::TYPES
  end

  # A new entry left on the column's default type, in a world without it,
  # takes the world's plain type instead.
  def default_to_plain_type
    self.base_type = world.type_chart.plain if world && base_type == "normal" && !world.type_chart.include?("normal")
  end

  # Variant recipe: hue shift in degrees, scale in percent, horizontal flip.
  # One image yields palette-swap variants.
  def variant=(recipe)
    recipe = (recipe || {}).to_h.stringify_keys
    super({
      "hue" => JsonCasting.integer(recipe["hue"]),
      "scale" => JsonCasting.integer(recipe["scale"]),
      "flip" => ActiveModel::Type::Boolean.new.cast(recipe["flip"]) || nil
    }.compact.reject { |key, value| (key == "hue" && value.zero?) || (key == "scale" && value == 100) })
  end

  private

  def default_slug
    self.slug = name.to_s.parameterize(separator: "_").sub(/\A[^a-z]+/, "") if slug.blank?
  end

  def variant_is_a_recipe
    hue = variant["hue"]
    scale = variant["scale"]
    errors.add(:variant, "hue must be a whole number between -180 and 180") if hue && !(hue.is_a?(Integer) && hue.between?(-180, 180))
    errors.add(:variant, "scale must be a whole percent between 25 and 400") if scale && !(scale.is_a?(Integer) && scale.between?(25, 400))
  end
end
