# frozen_string_literal: true

# Anything that can speak at the table: it has a portrait per expression,
# and falls back to neutral, then to #fallback_portrait_entry (a book
# entry's image), then to a lettered plate in the view.
module Portrayed
  extend ActiveSupport::Concern

  included do
    has_many :portraits, as: :owner, dependent: :destroy
  end

  # The image attachment for an expression, or nil.
  def portrait_image(expression = "neutral")
    by_expression = portraits.includes(image_attachment: :blob).index_by(&:expression)
    [ expression, "neutral" ].each do |key|
      image = by_expression[key.to_s]&.image
      return image if image&.attached?
    end
    fallback = fallback_portrait_entry
    fallback.image if fallback&.image&.attached?
  end

  def fallback_portrait_entry
    nil
  end

  # uploads:  { "happy" => <file>, ... }
  # removals: [ "angry", ... ]
  def update_portraits!(uploads: {}, removals: [])
    transaction do
      portraits.where(expression: removals).destroy_all
      uploads.each do |expression, file|
        next if file.blank?

        portrait = portraits.find_or_initialize_by(expression: expression.to_s)
        portrait.image.attach(file)
        portrait.save!
      end
    end
  end
end
