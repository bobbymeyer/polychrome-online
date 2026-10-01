# frozen_string_literal: true

# The GM says a line the world offered (Campaign::Remarks): from the GM seat
# only, and only once.
class Messages::SayingsController < ApplicationController
  include TableSeat

  def create
    note = Message.find(params[:message_id])
    @campaign = note.campaign
    return head(:forbidden) unless table_gm?

    @campaign.say_offer!(note)
    note.broadcast_replace_to(@campaign, :gm, partial: "messages/message", locals: { message: note })
    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_back_or_to campaign_table_path(@campaign), status: :see_other }
    end
  rescue Refusal => e
    redirect_back_or_to campaign_table_path(@campaign), alert: e.message, status: :see_other
  end
end
