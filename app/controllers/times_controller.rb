# frozen_string_literal: true

# The GM passes time at the table (Timekeeping).
class TimesController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def update
    return head :forbidden unless table_gm?

    parts = params[:until] == "dawn" ? @campaign.until_dawn : params[:parts].to_i.clamp(1, 28)
    @campaign.pass_time!(parts)
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
