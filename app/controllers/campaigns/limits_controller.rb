# frozen_string_literal: true

# A line or a veil for this table (Campaign::Limits), from any seat, with no
# name on it: whoever plays here may draw one, from the table or the
# campaign's page.
class Campaigns::LimitsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def create
    return head(:forbidden) unless plays_here?

    drawn = @campaign.draw_limit!(params[:kind], params[:text])
    redirect_back_or_to campaign_path(@campaign), notice: (drawn ? "Drawn, with no name on it." : "That one is already there."), status: :see_other
  rescue Refusal => e
    redirect_back_or_to campaign_path(@campaign), alert: e.message, status: :see_other
  end

  private

  def plays_here?
    table_seat.seated? || can_gm?(@campaign) || (current_user && @campaign.characters.exists?(user: current_user))
  end
end
