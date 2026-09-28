# frozen_string_literal: true

# A new local co-op join code: the old QR code and link stop working.
class Campaigns::JoinCodesController < ApplicationController
  include CampaignScoped

  before_action :set_campaign
  before_action :require_campaign_gm

  def create
    @campaign.new_join_code!
    redirect_to campaign_table_path(@campaign), notice: "New join code: #{@campaign.join_code}.", status: :see_other
  end
end
