# frozen_string_literal: true

# The GM's call on a rolled encounter: fight it, or wave it off (logged at
# the table either way).
class Campaigns::EncountersController < ApplicationController
  include CampaignScoped
  include MapGm

  before_action :set_campaign, :require_gm

  def create
    seconds = params[:input_seconds].presence&.to_i
    battle = @campaign.start_pending_encounter!(input_seconds: (seconds if BattleRecord::INPUT_TIMERS.include?(seconds)))
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
