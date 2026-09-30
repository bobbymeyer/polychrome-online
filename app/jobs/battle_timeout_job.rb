# frozen_string_literal: true

# The input timer (§5, §9.3). When a round's deadline passes, missing
# commands default to each unit's last command (or Attack) and the round
# runs. A job for a round that already ran does nothing, and so does one
# that comes while the GM is ruling on an idea (the clock resumes after).
# With nobody watching the battle, the round waits instead (BattleRecord#hold_clock!).
class BattleTimeoutJob < ApplicationJob
  def perform(battle, round)
    return if battle.deadline_at.nil? || battle.deadline_at > 1.second.from_now || battle.ruling_pending? || battle.round != round
    return battle.hold_clock! unless battle.watched?

    battle.apply!({ "type" => "timeout" }, actor: "system", if_round: round)
  end
end
