# frozen_string_literal: true

# The GM calls what kind of moment the table is in (Campaign::Controls):
# talk, travel, or things to do here. Everyone's panels follow.
class Campaigns::ControlsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def update
    return head(:forbidden) unless table_gm?

    @campaign.call_controls!(params[:kind].to_s)
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  rescue Refusal => e
    redirect_back_or_to campaign_table_path(@campaign), alert: e.message, status: :see_other
  end
end
