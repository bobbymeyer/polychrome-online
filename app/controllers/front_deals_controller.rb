# frozen_string_literal: true

# Dealing one of the setting's fronts into a campaign (WorldFront#deal!).
class FrontDealsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def create
    return head :forbidden unless table_gm?

    front = @world.world_fronts.find(params.expect(:front_id))
    front.deal!(@campaign)
    redirect_to campaign_path(@campaign, anchor: "clocks"), notice: "#{front.name} is in play.", status: :see_other
  rescue ArgumentError => e
    redirect_to campaign_path(@campaign, anchor: "clocks"), alert: e.message, status: :see_other
  end
end
