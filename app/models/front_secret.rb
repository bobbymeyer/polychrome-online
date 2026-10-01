# frozen_string_literal: true

# One of a front's secrets (WorldFront), about a place or someone in the
# setting. Dealt into a campaign it becomes a Secret, with its steps (Clue)
# and key.
class FrontSecret < ApplicationRecord
  belongs_to :world_front
  belongs_to :place, class_name: "WorldPlace", optional: true
  belongs_to :figure, class_name: "WorldFigure", optional: true

  normalizes :body, with: ->(body) { body.to_s.strip }
  normalizes :steps, with: ->(text) { text.to_s.strip.presence }
  normalizes :key, with: ->(key) { key.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "").presence }

  validates :body, presence: true
  validates :key, format: { with: Flag::KEY_FORMAT, message: "must start with a letter: letters, digits and underscores" }, allow_nil: true
  validate { Clue.parse(steps).last.each { |problem| errors.add(:steps, problem) } }
  validate do
    errors.add(:place, "isn't in this setting's atlas") if place && place.world_id != world_front.world_id
    errors.add(:figure, "isn't in this setting's cast") if figure && figure.world_id != world_front.world_id
  end
end
