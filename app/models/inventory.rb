# frozen_string_literal: true

# One row of a bag: how many of an item a character carries, or, with no
# character, how many the party's chest holds.
class Inventory < ApplicationRecord
  include CampaignPages

  belongs_to :campaign
  belongs_to :character, optional: true
  belongs_to :item

  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :item_id, uniqueness: { scope: %i[campaign_id character_id] }
  validate { errors.add(:character, "isn't in this party") if character && character.campaign_id != campaign_id }

  def chest? = character_id.nil?
end
