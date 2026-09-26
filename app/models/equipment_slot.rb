# frozen_string_literal: true

# What a character has in one equipment slot.
class EquipmentSlot < ApplicationRecord
  belongs_to :character
  belongs_to :item

  validates :slot, inclusion: { in: Item::CATEGORIES.values.compact.uniq }, uniqueness: { scope: :character_id }
end
