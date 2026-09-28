# frozen_string_literal: true

# Something people are saying, travelling the map a road a day from where it
# started (Pointcrawl::Overnight), until it fades. The party hears it when
# they reach a place it has got to, or buys it at a guild. The GM sees
# every rumour and how far it has gone.
class Rumour < ApplicationRecord
  belongs_to :campaign
  belongs_to :origin, class_name: "MapNode", optional: true
  belongs_to :deed, optional: true
  belongs_to :secret, optional: true
  belongs_to :heard_at, class_name: "MapNode", optional: true
  has_many :rumour_places, -> { order(:id) }, dependent: :delete_all
  has_many :places, through: :rumour_places, source: :map_node

  normalizes :body, with: ->(body) { body.to_s.strip }

  validates :body, presence: true, length: { maximum: 500 }

  scope :travelling, -> { where(faded: false) }
  scope :unheard, -> { where(heard: false) }
  scope :at, ->(node) { where(id: RumourPlace.where(map_node: node).select(:rumour_id)) }
  scope :about_deeds, -> { where.not(deed_id: nil) }

  # The ids of the places it has got to, in the order it got there.
  def reached = rumour_places.map(&:map_node_id)

  def reached?(node) = rumour_places.any? { |place| place.map_node_id == node.id }

  # It gets to these places (map nodes or their ids) on this day.
  def reach!(nodes, day:)
    ids = Array(nodes).map { |node| node.is_a?(MapNode) ? node.id : node } - reached
    ids.each { |id| rumour_places.create!(map_node_id: id, day: day) }
  end
end
