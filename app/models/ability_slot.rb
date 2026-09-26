# frozen_string_literal: true

# A learned ability equipped into one of the current job's free slots, so
# it can be used outside the job that taught it (FF5-style).
class AbilitySlot < ApplicationRecord
  belongs_to :character
  belongs_to :ability

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, uniqueness: { scope: :character_id }
end
