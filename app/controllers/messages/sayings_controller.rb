# frozen_string_literal: true

# The GM says a line the world offered (Campaign::Remarks): from the GM seat
# only, and only once.
class Messages::SayingsController < ApplicationController
  before_action :set_note
  before_action :require_table_gm

  def create
    @campaign.say_offer!(@note)
    @note.broadcast_replace_to(@campaign, :gm, partial: "messages/message", locals: { message: @note })
    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_back_or_to campaign_table_path(@campaign), status: :see_other }
    end
  end

  private

  def set_note
    @note = Message.find(params[:message_id])
    @campaign = @note.campaign
  end
end
