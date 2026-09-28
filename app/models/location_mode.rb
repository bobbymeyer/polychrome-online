# frozen_string_literal: true

# One of a place's other states (Location::Modes): prepared by the GM and
# set off at the table. The city burns, the mine floods, the festival
# starts. While it lasts, some services are shut, the music changes, there
# can be trouble on arrival, and players read a line about it. Clocks,
# scenes and its picture point at it.
class LocationMode < ApplicationRecord
  belongs_to :location, touch: true
  belongs_to :encounter_table, optional: true
  has_one :mode_art, dependent: :destroy
  has_many :clocks, dependent: :nullify
  has_many :scenes, dependent: :nullify

  normalizes :name, with: ->(name) { name.to_s.strip }
  normalizes :line, :description, :art, with: ->(text) { text.to_s.strip.presence }
  normalizes :music, with: ->(music) { music.presence }

  before_validation { self.key = name.parameterize(separator: "_") if key.blank? && name.present? }

  validates :name, presence: true
  validates :key, presence: true, uniqueness: { scope: :location_id }
  validates :music, inclusion: { in: Campaign::MUSIC_CHOICES }, allow_nil: true
  validate :trouble_from_this_world

  def closed=(kinds)
    super(Array(kinds).compact_blank.map(&:to_s))
  end

  def shuts?(kind) = closed.include?(kind.to_s)

  private

  def trouble_from_this_world
    return unless encounter_table && location

    errors.add(:encounter_table, "isn't one of #{location.campaign.world.name}'s") unless encounter_table.world_id == location.campaign.world_id
  end
end
