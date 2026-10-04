# frozen_string_literal: true

# "to_map is <direction> of from_map", in a campaign: read the other way
# too (MapSheet#neighbours).
class MapLink < ApplicationRecord
  belongs_to :campaign
  belongs_to :from_map, class_name: "Map", inverse_of: :links_out
  belongs_to :to_map, class_name: "Map", inverse_of: :links_in

  validates :direction, inclusion: { in: MapSheet::DIRECTIONS }
  validate :joins_two_maps_once

  after_commit { campaign.table_changed }

  private

  def joins_two_maps_once
    errors.add(:to_map, "must be another map") if from_map_id == to_map_id
    [ from_map, to_map ].compact.each { |map| errors.add(:base, "#{map.name} isn't this campaign's") if map.campaign_id != campaign_id }
    pair = MapLink.where(from_map_id: from_map_id, to_map_id: to_map_id).or(MapLink.where(from_map_id: to_map_id, to_map_id: from_map_id))
    errors.add(:base, "Those two maps are already side by side") if pair.where.not(id: id).exists?
  end
end
