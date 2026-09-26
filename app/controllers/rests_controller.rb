# frozen_string_literal: true

class RestsController < ApplicationController
  include CampaignScoped

  before_action :set_campaign

  def create
    @campaign.rest!
    redirect_to campaign_path(@campaign), notice: "The party rests. Everyone is back to full.", status: :see_other
  end
end
