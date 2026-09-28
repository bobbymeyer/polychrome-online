# frozen_string_literal: true

# One of a front's secrets (WorldFront), about a place or someone in the
# setting. Dealt into a campaign it becomes a Secret.
class FrontSecret < ApplicationRecord
  belongs_to :world_front
  belongs_to :place, class_name: "WorldPlace", optional: true
  belongs_to :figure, class_name: "WorldFigure", optional: true

  normalizes :body, with: ->(body) { body.to_s.strip }

  validates :body, presence: true
  validate do
    errors.add(:place, "isn't in this setting's atlas") if place && place.world_id != world_front.world_id
    errors.add(:figure, "isn't in this setting's cast") if figure && figure.world_id != world_front.world_id
  end
end
