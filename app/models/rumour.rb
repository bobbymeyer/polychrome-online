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

  normalizes :body, with: ->(body) { body.to_s.strip }

  validates :body, presence: true, length: { maximum: 500 }

  scope :travelling, -> { where(faded: false) }
  scope :unheard, -> { where(heard: false) }

  def reached?(node) = reached.include?(node.id)

  def places
    campaign.map_nodes.where(id: reached).order(:name)
  end
end
