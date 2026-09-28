# frozen_string_literal: true

# Something the party did that people will talk about: beat an antagonist
# for good, cleared a dungeon, or whatever the GM says counts. Each starts a
# rumour where it happened (Campaign::Deeds), and a town's view of the party
# is the sway of the deeds whose news has got there: heroic up, dark down.
class Deed < ApplicationRecord
  KINDS = %w[gm antagonist cleared].freeze
  SWAYS = -2..2

  include CampaignPages

  belongs_to :campaign
  belongs_to :map_node, optional: true
  # Striking a deed takes its story with it, and so what the towns it
  # reached thought of the party (Location::Town#reputation).
  has_many :rumours, dependent: :destroy

  normalizes :body, with: ->(body) { body.to_s.strip }

  validates :body, presence: true, length: { maximum: 300 }
  validates :kind, inclusion: { in: KINDS }
  validates :sway, inclusion: { in: SWAYS }

  scope :in_order, -> { order(:day, :id) }
end
