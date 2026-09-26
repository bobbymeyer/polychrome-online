# frozen_string_literal: true

# The campaign's table: one long-lived page (§9.9) with the dialogue box, the
# log and a composer for whoever is sitting here.
class TablesController < ApplicationController
  include CampaignScoped
  include TableSeat

  LOG_LENGTH = 80

  before_action :set_campaign

  def show
    @seat = table_seat
    @messages = Message.visible_to(@campaign, @seat).last(LOG_LENGTH)
    @last_dialogue = @messages.reverse.find(&:dialogue?)
    @battle = @campaign.battles.where(status: "input").order(created_at: :desc).first
  end
end
