# frozen_string_literal: true

# The GM puts a finished duel's result away (Duel#close!).
class Campaigns::DuelsController < Campaigns::BaseController
  before_action :require_table_gm

  def update
    @campaign.duels.find(params[:id]).close!
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
