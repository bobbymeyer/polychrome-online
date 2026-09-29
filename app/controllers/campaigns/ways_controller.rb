# frozen_string_literal: true

# Where the party goes next (Campaign::Ways). A player suggests a way: it
# goes to the table as a "Where next?" vote with their pick in it. Anyone
# seated can put the question without a pick. The GM can also just go.
class Campaigns::WaysController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def create
    seat = table_seat
    return head(:forbidden) unless seat.seated?

    if seat.gm? && params[:go].present?
      @campaign.take_way!(params[:way])
    else
      vote = @campaign.ask_where_next!
      vote.picks.find_or_initialize_by(character: seat.character).update!(option: params[:way]) if seat.character? && params[:way].present?
    end
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  rescue Refusal, ActiveRecord::RecordInvalid => e
    redirect_back_or_to campaign_table_path(@campaign), alert: e.message, status: :see_other
  end
end
