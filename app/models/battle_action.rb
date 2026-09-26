# frozen_string_literal: true

# One action the resolver accepted, in order. `actor` is the party unit
# that submitted it, "gm" for overrides, or "system" for the input timer.
class BattleAction < ApplicationRecord
  belongs_to :battle, class_name: "BattleRecord", inverse_of: :battle_actions
  has_many :battle_events, dependent: :delete_all

  validates :position, presence: true, uniqueness: { scope: :battle_id }
  validates :actor, presence: true
end
