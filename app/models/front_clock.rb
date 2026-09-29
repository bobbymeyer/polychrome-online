# frozen_string_literal: true

# One of a front's clocks (WorldFront), written once in the setting. Dealt
# into a campaign it becomes a Clock; if it names a place and a mode, that
# place gets the mode, and the clock sets it off when it fills.
class FrontClock < ApplicationRecord
  belongs_to :world_front
  belongs_to :place, class_name: "WorldPlace", optional: true
  # The place behind it: clearing it stops the dealt clock (Clock#map_node).
  belongs_to :source, class_name: "WorldPlace", optional: true

  normalizes :name, with: ->(name) { name.to_s.strip }
  normalizes :full_line, :mode_name, :mode_line, :mode_description, with: ->(text) { text.to_s.strip.presence }

  validates :name, presence: true
  validates :segments, numericality: { only_integer: true, in: 2..12 }
  validate { errors.add(:place, "isn't in this setting's atlas") if place && place.world_id != world_front.world_id }

  def triggers=(value)
    super(Array(value).map(&:to_s) & Clock::TRIGGERS.keys)
  end
end
