# frozen_string_literal: true

# The next of a secret's clues comes out because the GM says so
# (Secret#find_clue!): from their secrets, or the moves panel.
class Campaigns::Secrets::CluesController < Campaigns::BaseController
  before_action :require_campaign_gm # Prep is the GM's account's, seated or not (TableSeat)

  def create
    @campaign.secrets.find(params[:secret_id]).find_clue!
    back
  rescue Refusal => e
    back alert: e.message
  end

  private

  def back(alert: nil)
    redirect_back_or_to campaign_prep_path(@campaign, anchor: "secrets"), alert: alert, status: :see_other
  end
end
