# frozen_string_literal: true

# One map of a setting's atlas (docs/HANDOFF.md §7, "Maps"): the world, a
# region on it, a town on that. Its places (WorldPlace) and child maps sit
# on it; its siblings are off its edges (WorldMapLink). A campaign starts
# with copies of them all (Atlas, Map).
class WorldMap < ApplicationRecord
  belongs_to :world
  belongs_to :parent, class_name: "WorldMap", optional: true
  has_many :children, class_name: "WorldMap", foreign_key: :parent_id, dependent: :nullify, inverse_of: :parent
  has_many :world_places, dependent: :nullify
  has_many :links_out, class_name: "WorldMapLink", foreign_key: :from_map_id, dependent: :destroy, inverse_of: :from_map
  has_many :links_in, class_name: "WorldMapLink", foreign_key: :to_map_id, dependent: :destroy, inverse_of: :to_map
  has_many :maps, dependent: :nullify # the campaigns' copies

  include Artwork
  include MapSheet

  validates :name, uniqueness: { scope: :world_id }
  validate { errors.add(:parent, "isn't one of #{world.name}'s maps") if parent && parent.world_id != world_id }

  scope :in_order, -> { order(:id) }

  def art_world = world
  def art_stream = self
  def places = world_places

  def nodes_for(_gm = true)
    world_places.includes(:location_template).order(:id).to_a
  end

  def edges_among(places)
    ids = places.map(&:id)
    world.world_routes.includes(:from_place, :to_place, :encounter_table).order(:id).select { |r| ids.include?(r.from_place_id) && ids.include?(r.to_place_id) }
  end
end
