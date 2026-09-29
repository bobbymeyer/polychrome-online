# frozen_string_literal: true

# The GM's call after the whole party has fallen (Campaign::Defeat).
class Campaigns::RecoveriesController < ApplicationController
  include CampaignScoped

  before_action :set_campaign
  before_action :require_campaign_gm

  def create
    @campaign.recover!(params.expect(:how))
    redirect_to campaign_table_path(@campaign), status: :see_other
  rescue Refusal => e
    redirect_to campaign_table_path(@campaign), alert: e.message, status: :see_other
  end
end
