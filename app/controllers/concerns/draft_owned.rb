# frozen_string_literal: true

# Loads what a draft (Draft) belongs to: a campaign, whose GM it is for, or
# a world, whose editors it is for. Nested under either.
module DraftOwned
  extend ActiveSupport::Concern

  included do
    before_action :set_owner
  end

  private

  def set_owner
    if params[:campaign_id]
      @owner = Campaign.find(params[:campaign_id])
      head :forbidden unless can_gm?(@owner) # prep is the account's, seated or not (TableSeat)
    else
      @owner = World.find_by!(slug: params[:world_slug])
      head :forbidden unless can_edit_world?(@owner)
    end
  end

  def back(notice: nil, alert: nil)
    fallback = @owner.is_a?(Campaign) ? campaign_path(@owner) : world_path(@owner)
    redirect_back_or_to fallback, notice: notice, alert: alert, status: :see_other
  end
end
