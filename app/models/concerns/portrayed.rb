# frozen_string_literal: true

# Anything that can speak at the table: it has a portrait per expression,
# and falls back to neutral, then to #fallback_portrait_entry (a book
# entry's image), then to a lettered plate in the view. On the stage it
# stands full body as its sprite (Sprite), or #fallback_sprite_entry's
# image, or its portrait.
module Portrayed
  extend ActiveSupport::Concern

  included do
    has_many :portraits, as: :owner, dependent: :destroy
    has_one :sprite, as: :owner, dependent: :destroy
  end

  # The full-body image for the stage, or nil (the portrait stands in).
  def sprite_image
    return sprite.image if sprite&.image&.attached?

    fallback = fallback_sprite_entry
    fallback.image if fallback&.image&.attached?
  end

  def fallback_sprite_entry
    nil
  end

  # The image attachment for an expression, or nil.
  def portrait_image(expression = "neutral")
    own = own_portrait_image(expression)
    return own if own

    fallback = fallback_portrait_entry
    fallback.image if fallback&.image&.attached?
  end

  # Their own portrait for an expression, or their neutral one; nil when
  # they have neither (no fallback).
  def own_portrait_image(expression = "neutral")
    by_expression = (portraits.loaded? ? portraits : portraits.includes(image_attachment: :blob)).index_by(&:expression)
    [ expression, "neutral" ].each do |key|
      image = by_expression[key.to_s]&.image
      return image if image&.attached?
    end
    nil
  end

  def fallback_portrait_entry
    nil
  end

  # uploads:  { "happy" => <file>, ... }
  # removals: [ "angry", ... ]
  # sprite_upload: the full-body file; remove_sprite: take the sprite away.
  def update_portraits!(uploads: {}, removals: [], sprite_upload: nil, remove_sprite: false)
    transaction do
      portraits.where(expression: removals).destroy_all
      uploads.each do |expression, file|
        next if file.blank?

        portrait = portraits.find_or_initialize_by(expression: expression.to_s)
        portrait.image.attach(file)
        portrait.save!
      end
      sprite&.destroy! if remove_sprite
      if sprite_upload.present?
        figure = reload.sprite || build_sprite
        figure.image.attach(sprite_upload)
        figure.save!
      end
    end
  end
end
