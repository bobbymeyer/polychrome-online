# frozen_string_literal: true

# One resolver event, in battle order: the replay log (§4).
class BattleEvent < ApplicationRecord
  belongs_to :battle, class_name: "BattleRecord", inverse_of: :battle_events
  belongs_to :battle_action
end
