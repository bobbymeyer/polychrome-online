# frozen_string_literal: true

# A point on a campaign's pointcrawl map (§4, §7). Hidden until the GM
# reveals it or the party arrives.
class MapNode < ApplicationRecord
  KINDS = %w[town dungeon landmark wilds field event].freeze
  WIDTH = 1000
  HEIGHT = 700

  belongs_to :campaign
  belongs_to :location, optional: true
  belongs_to :world_place, optional: true
  has_many :home_characters, class_name: "Character", foreign_key: :home_node_id, dependent: :nullify, inverse_of: :home_node
  has_many :outgoing_edges, class_name: "MapEdge", foreign_key: :from_node_id, dependent: :destroy, inverse_of: :from_node
  has_many :incoming_edges, class_name: "MapEdge", foreign_key: :to_node_id, dependent: :destroy, inverse_of: :to_node
  # What's being said here, and the rumours the party heard here.
  has_many :rumour_places, dependent: :delete_all
  # Clocks this place is behind: clearing it stops them (Campaign#clear_place!).
  has_many :clocks, dependent: :nullify
  has_many :heard_rumours, class_name: "Rumour", foreign_key: :heard_at_id, dependent: :nullify, inverse_of: :heard_at

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :x, numericality: { only_integer: true, in: 0..WIDTH }
  validates :y, numericality: { only_integer: true, in: 0..HEIGHT }

  before_destroy { campaign.update_columns(current_node_id: nil) if campaign.current_node_id == id }
  after_commit { campaign.broadcast_map }

  def edges
    campaign.map_edges.where(from_node: self).or(campaign.map_edges.where(to_node: self))
  end

  def party_here?
    campaign.current_node_id == id
  end
end
