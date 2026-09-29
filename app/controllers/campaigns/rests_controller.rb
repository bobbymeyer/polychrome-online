# frozen_string_literal: true

class Campaigns::RestsController < ApplicationController
  include CampaignScoped

  before_action :set_campaign
  before_action :require_campaign_gm

  def create
    @campaign.rest!
    redirect_to campaign_path(@campaign), notice: "The party rests: full HP, and half their MP back.", status: :see_other
  rescue Refusal => e
    redirect_to campaign_path(@campaign), alert: e.message, status: :see_other
  end
end
