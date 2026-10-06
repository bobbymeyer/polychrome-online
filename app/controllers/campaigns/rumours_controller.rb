# frozen_string_literal: true

# The GM's rumours (Rumour): started by hand at a place, or hushed.
class Campaigns::RumoursController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action :require_campaign_gm # Prep is the GM's account's, seated or not (TableSeat)

  def create
    fields = params.expect(rumour: %i[body origin_id about_id])
    about = fields[:about_id].presence && @campaign.map_nodes.find(fields[:about_id])
    @campaign.start_rumour!(fields[:body], at: @campaign.map_nodes.find(fields[:origin_id]), about: about)
    @campaign.hear_rumours!
    back notice: "It's out there now."
  rescue ActiveRecord::RecordInvalid => e
    back alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    @campaign.rumours.find(params[:id]).update!(faded: true)
    back notice: "Hushed: nobody's saying that any more."
  end

  private

  def back(notice: nil, alert: nil)
    redirect_to campaign_prep_path(@campaign, anchor: "rumours"), notice: notice, alert: alert, status: :see_other
  end
end
