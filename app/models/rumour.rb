# frozen_string_literal: true

# Something people are saying, travelling the map a road a day from where it
# started (Pointcrawl::Overnight), until it fades. The party hears it when
# they reach a place it has got to, or buys it at a guild. The GM sees
# every rumour and how far it has gone.
#
# A deed is a rumour too: something the party did that people will talk
# about (Campaign::Deeds), told from where it happened, with the sway it
# carries. A town's view of the party is the sway of the deeds whose news
# has got there: heroic up, dark down. deed: what kind (the GM's, an
# antagonist beaten for good, a place cleared), or nil for any other rumour.
class Rumour < ApplicationRecord
  DEEDS = %w[gm antagonist cleared favour].freeze
  SWAYS = -2..2

  include CampaignPages

  belongs_to :campaign
  belongs_to :origin, class_name: "MapNode", optional: true
  belongs_to :secret, optional: true
  belongs_to :heard_at, class_name: "MapNode", optional: true
  # The place it's about, if it points somewhere: hearing it puts the place
  # on the map (Campaign#hear_of!).
  belongs_to :about, class_name: "MapNode", optional: true
  has_many :rumour_places, -> { order(:id) }, dependent: :delete_all
  has_many :places, through: :rumour_places, source: :map_node

  normalizes :body, with: ->(body) { body.to_s.strip }

  validates :body, presence: true, length: { maximum: 500 }
  validates :deed, inclusion: { in: DEEDS }, allow_nil: true
  validates :sway, inclusion: { in: SWAYS }

  scope :travelling, -> { where(faded: false) }
  scope :unheard, -> { where(heard: false) }
  scope :at, ->(node) { where(id: RumourPlace.where(map_node: node).select(:rumour_id)) }
  scope :deeds, -> { where.not(deed: nil) }
  scope :talk, -> { where(deed: nil) }
  scope :in_order, -> { order(:day, :id) }

  # The ids of the places it has got to, in the order it got there.
  def reached = rumour_places.map(&:map_node_id)

  def reached?(node) = rumour_places.any? { |place| place.map_node_id == node.id }

  # It gets to these places (map nodes or their ids) on this day.
  def reach!(nodes, day:)
    ids = Array(nodes).map { |node| node.is_a?(MapNode) ? node.id : node } - reached
    ids.each { |id| rumour_places.create!(map_node_id: id, day: day) }
  end
end
