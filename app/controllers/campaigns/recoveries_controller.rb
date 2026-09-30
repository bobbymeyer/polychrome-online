# frozen_string_literal: true

# After the whole party has fallen outside a battle (the GM set their HP),
# the GM puts "What happens now?" to the table (Campaign::Defeat); a lost
# battle puts it there by itself.
class Campaigns::RecoveriesController < ApplicationController
  include CampaignScoped

  before_action :set_campaign
  before_action :require_campaign_gm

  def create
    @campaign.ask_what_now!
    redirect_to campaign_table_path(@campaign), status: :see_other
  end
end
