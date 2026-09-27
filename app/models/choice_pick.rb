# frozen_string_literal: true

# One character's pick in a choice for the table. They can change their
# mind until the GM settles it.
class ChoicePick < ApplicationRecord
  belongs_to :message
  belongs_to :character

  validates :option, inclusion: { in: ->(pick) { pick.message&.options || [] } }
  validates :character_id, uniqueness: { scope: :message_id }
  validate :still_open
  validate :at_this_table

  after_commit { message.broadcast_choice }

  private

  def still_open
    errors.add(:message, "has been settled") unless message&.open_choice?
  end

  def at_this_table
    errors.add(:character, "isn't at this table") if message && character && character.campaign_id != message.campaign_id
  end
end
