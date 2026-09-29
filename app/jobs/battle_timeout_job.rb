# frozen_string_literal: true

# The input timer (§5, §9.3). When a round's deadline passes, missing
# commands default to each unit's last command (or Attack) and the round
# runs. A job for a round that already ran does nothing, and so does one
# that comes while the GM is ruling on an idea (the clock resumes after).
class BattleTimeoutJob < ApplicationJob
  def perform(battle, round)
    return if battle.deadline_at.nil? || battle.deadline_at > 1.second.from_now || battle.ruling_pending?

    battle.apply!({ "type" => "timeout" }, actor: "system", if_round: round)
  end
end
