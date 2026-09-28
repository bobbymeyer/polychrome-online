# frozen_string_literal: true

# Anything with art of its own (Art): book entries, speakers, the cast,
# portraits and mode pictures. Its art is read and written as if it were
# its own columns (art_notes, art_loras, art_model, image_seed,
# image_prompt, image_recipe), and saved with it. Reading never makes an
# Art; writing something does.
module Drawn
  extend ActiveSupport::Concern

  FIELDS = { art_notes: :notes, art_loras: :loras, art_model: :model, image_seed: :seed, image_prompt: :prompt, image_recipe: :recipe }.freeze

  included do
    has_one :art, as: :subject, class_name: "::Art", dependent: :destroy, autosave: true
  end

  FIELDS.each do |mine, its|
    define_method(mine) do
      value = art&.public_send(its)
      its == :loras ? Array(value) : value
    end

    define_method(:"#{mine}=") do |value|
      return if art.nil? && (value.blank? || value == [])

      (art || build_art).public_send(:"#{its}=", value)
    end
  end
end
