# frozen_string_literal: true

# One row of the party bag: how many of an item the party carries.
class Inventory < ApplicationRecord
  include CampaignPages

  belongs_to :campaign
  belongs_to :item

  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :item_id, uniqueness: { scope: :campaign_id }
end
