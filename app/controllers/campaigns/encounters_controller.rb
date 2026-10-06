# frozen_string_literal: true

# The GM's call on a rolled encounter: fight it, or wave it off (logged at
# the table either way).
class Campaigns::EncountersController < Campaigns::BaseController
  include MapGm

  before_action :require_table_gm

  def create
    seconds = params[:input_seconds].presence&.to_i
    prelude = params[:prelude].to_s.lines.map(&:strip).compact_blank.first(Campaign::PRELUDE_LINES)
    battle = @campaign.start_pending_encounter!(input_seconds: (seconds if BattleRecord::INPUT_TIMERS.include?(seconds)), prelude: prelude)
    redirect_to battle_path(battle), status: :see_other
  rescue Refusal => e
    panel alert: e.message
  end

  def destroy
    @campaign.wave_off_encounter!
    back_to = url_from(params[:return_to])
    back_to ? redirect_to(back_to, notice: "Encounter waved off.", status: :see_other) : panel(notice: "Encounter waved off.")
  end
end
