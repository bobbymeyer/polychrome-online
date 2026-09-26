# frozen_string_literal: true

class TableSeatsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def create
    claim_table_seat(@campaign, params.expect(:seat))
    redirect_to campaign_table_path(@campaign), status: :see_other
  end

  def destroy
    leave_table_seat(@campaign)
    redirect_to campaign_table_path(@campaign), status: :see_other
  end
end
