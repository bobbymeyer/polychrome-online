# frozen_string_literal: true

# A clock going on a segment by hand, or back one (Clock#tick!).
class Campaigns::Clocks::TicksController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action :require_campaign_gm # Prep is the GM's account's, seated or not (TableSeat)

  def create
    @campaign.clocks.find(params[:clock_id]).tick!(params[:by].to_i.clamp(-12, 12))
    redirect_back_or_to campaign_prep_path(@campaign, anchor: "clocks"), status: :see_other
  end
end
