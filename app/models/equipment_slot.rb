# frozen_string_literal: true

# What a character has in one equipment slot.
class EquipmentSlot < ApplicationRecord
  belongs_to :character
  belongs_to :item

  validates :slot, inclusion: { in: Item::SLOTS }, uniqueness: { scope: :character_id }
  validate :item_goes_there

  private

  def item_goes_there
    return if item.nil? || item.slots.include?(slot)

    errors.add(:slot, "isn't where #{item.name} is worn")
  end
end
