# frozen_string_literal: true

# A new invite code: the old link and QR code stop working.
class Campaigns::JoinCodesController < ApplicationController
  include CampaignScoped

  before_action :set_campaign
  before_action :require_campaign_gm

  def create
    @campaign.new_join_code!
    redirect_to campaign_path(@campaign, anchor: "invite"), notice: "New invite code: #{@campaign.join_code}. The old link and QR code no longer work.", status: :see_other
  end
end
