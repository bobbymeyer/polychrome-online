# frozen_string_literal: true

# A road in a setting's atlas, between two of its places, with what waits on
# it. Brought into a campaign as a map path (Atlas).
class WorldRoute < ApplicationRecord
  belongs_to :world
  belongs_to :from_place, class_name: "WorldPlace"
  belongs_to :to_place, class_name: "WorldPlace"
  belongs_to :encounter_table, optional: true

  validates :state, inclusion: { in: MapEdge::STATES }
  validates :duration, numericality: { only_integer: true, in: 1..28 }
  validate :joins_two_places_of_the_world

  def label = "#{from_place.name} – #{to_place.name}"

  private

  def joins_two_places_of_the_world
    errors.add(:to_place, "must be another place") if from_place_id == to_place_id
    [ from_place, to_place, encounter_table ].compact.each do |record|
      errors.add(:base, "#{record.name} isn't #{world.name}'s") if record.world_id != world_id
    end
  end
end
