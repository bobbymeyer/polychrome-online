# frozen_string_literal: true

# A secret the party has learned: revealed at the table, or put back when
# the GM revealed it by mistake (Secret#reveal!, #conceal!).
class Campaigns::Secrets::RevelationsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action :require_campaign_gm # Prep is the GM's account's, seated or not (TableSeat)
  before_action :set_secret

  def create
    @secret.reveal!
    back
  rescue Refusal => e
    back alert: e.message
  end

  def destroy
    @secret.conceal!
    back notice: "Put back: the party doesn't know that after all."
  end

  private

  def set_secret
    @secret = @campaign.secrets.find(params[:secret_id])
  end

  def back(notice: nil, alert: nil)
    redirect_back_or_to campaign_prep_path(@campaign, anchor: "secrets"), notice: notice, alert: alert, status: :see_other
  end
end
