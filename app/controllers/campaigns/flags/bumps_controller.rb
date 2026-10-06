# frozen_string_literal: true

# Nudging a counter flag up or down at the table (Flag#bump!).
class Campaigns::Flags::BumpsController < Campaigns::BaseController
  before_action :require_campaign_gm # Prep is the GM's account's, seated or not (TableSeat)

  def create
    @campaign.flags.find(params[:flag_id]).bump!(params[:by].to_i.clamp(-100, 100))
    redirect_to campaign_prep_path(@campaign, anchor: "flags"), status: :see_other
  rescue Refusal => e
    redirect_to campaign_prep_path(@campaign, anchor: "flags"), alert: e.message, status: :see_other
  end
end
