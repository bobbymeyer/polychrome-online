# frozen_string_literal: true

# Dealing one of the setting's fronts into a campaign (WorldFront#deal!).
class Campaigns::FrontDealsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action :require_table_gm

  def create
    front = @world.world_fronts.find(params.expect(:front_id))
    front.deal!(@campaign)
    redirect_to campaign_prep_path(@campaign, anchor: "clocks"), notice: "#{front.name} is in play.", status: :see_other
  rescue Refusal => e
    redirect_to campaign_prep_path(@campaign, anchor: "clocks"), alert: e.message, status: :see_other
  end
end
