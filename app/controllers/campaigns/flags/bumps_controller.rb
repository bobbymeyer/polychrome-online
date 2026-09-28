# frozen_string_literal: true

# Nudging a counter flag up or down at the table (Flag#bump!).
class Campaigns::Flags::BumpsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action -> { head :forbidden unless table_gm? }

  def create
    @campaign.flags.find(params[:flag_id]).bump!(params[:by].to_i.clamp(-100, 100))
    redirect_to campaign_path(@campaign, anchor: "flags"), status: :see_other
  rescue Refusal => e
    redirect_to campaign_path(@campaign, anchor: "flags"), alert: e.message, status: :see_other
  end
end
