# frozen_string_literal: true

class TableSeatsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def create
    seat = params.expect(:seat)
    take_table_seat(@campaign, seat) if seat == "gm" || @campaign.characters.exists?(id: seat)
    redirect_to campaign_table_path(@campaign), status: :see_other
  end

  def destroy
    leave_table_seat(@campaign)
    redirect_to campaign_table_path(@campaign), status: :see_other
  end
end
