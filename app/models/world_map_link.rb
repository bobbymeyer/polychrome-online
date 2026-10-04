# frozen_string_literal: true

# "to_map is <direction> of from_map", on a setting's atlas: read the other
# way too (MapSheet#neighbours).
class WorldMapLink < ApplicationRecord
  belongs_to :world
  belongs_to :from_map, class_name: "WorldMap", inverse_of: :links_out
  belongs_to :to_map, class_name: "WorldMap", inverse_of: :links_in

  validates :direction, inclusion: { in: MapSheet::DIRECTIONS }
  validate :joins_two_maps_once

  private

  def joins_two_maps_once
    errors.add(:to_map, "must be another map") if from_map_id == to_map_id
    [ from_map, to_map ].compact.each { |map| errors.add(:base, "#{map.name} isn't #{world.name}'s") if map.world_id != world_id }
    pair = WorldMapLink.where(from_map_id: from_map_id, to_map_id: to_map_id).or(WorldMapLink.where(from_map_id: to_map_id, to_map_id: from_map_id))
    errors.add(:base, "Those two maps are already side by side") if pair.where.not(id: id).exists?
  end
end
