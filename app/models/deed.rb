# frozen_string_literal: true

# Something the party did that people will talk about: beat an antagonist
# for good, cleared a dungeon, or whatever the GM says counts. Each starts a
# rumour where it happened (Campaign::Deeds), and a town's view of the party
# moves by its sway as the news gets there: heroic deeds up, dark ones down.
class Deed < ApplicationRecord
  KINDS = %w[gm antagonist cleared].freeze
  SWAYS = -2..2

  belongs_to :campaign
  belongs_to :map_node, optional: true
  has_many :rumours, dependent: :nullify

  normalizes :body, with: ->(body) { body.to_s.strip }

  validates :body, presence: true, length: { maximum: 300 }
  validates :kind, inclusion: { in: KINDS }
  validates :sway, inclusion: { in: SWAYS }

  scope :in_order, -> { order(:day, :id) }
end
