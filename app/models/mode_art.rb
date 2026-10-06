# frozen_string_literal: true

# A location mode's picture (§8), uploaded by the GM: while the mode lasts,
# the table sees it instead of the place's Gazetteer image (Location#picture).
class ModeArt < ApplicationRecord
  belongs_to :location
  belongs_to :mode
  has_one_attached :image

  validates :mode, uniqueness: true

  delegate :key, to: :mode, prefix: :mode
end
