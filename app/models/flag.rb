# frozen_string_literal: true

# A campaign flag (§4): a named piece of GM state, like
# `met_the_king = yes` or `crystals_found = 2`. Values are text; a whole
# number can be counted up and down.
class Flag < ApplicationRecord
  KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

  belongs_to :campaign

  normalizes :key, with: ->(key) { key.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "") }
  normalizes :value, with: ->(value) { value.to_s.strip }

  validates :key, presence: true, uniqueness: { scope: :campaign_id },
                  format: { with: KEY_FORMAT, message: "must start with a letter: letters, digits and underscores" }
  validates :value, length: { maximum: 500 }

  scope :shown_to_players, -> { where(public: true) }

  def counter?
    value.match?(/\A-?\d+\z/)
  end

  def bump!(by)
    raise Refusal, "#{key} isn't a number" unless counter?

    update!(value: (value.to_i + by).to_s)
  end

  def label
    key.humanize
  end
end
