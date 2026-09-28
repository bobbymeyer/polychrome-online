# frozen_string_literal: true

# The GM's record of what the party did (Campaign::Deeds): written at the
# table, or struck when it was a mistake. Its story goes with it, and so
# does what the towns it reached thought of the party.
class Campaigns::DeedsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action -> { head :forbidden unless table_gm? }

  def create
    fields = params.expect(deed: %i[body map_node_id sway])
    at = fields[:map_node_id].present? ? @campaign.map_nodes.find(fields[:map_node_id]) : @campaign.current_node
    @campaign.record_deed!(fields[:body], at: at, sway: fields[:sway].to_i.clamp(Deed::SWAYS.min, Deed::SWAYS.max))
    back notice: "Done, and people will talk."
  rescue ActiveRecord::RecordInvalid => e
    back alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    @campaign.deeds.find(params[:id]).destroy!
    back notice: "Struck: it never happened."
  end

  private

  def back(notice: nil, alert: nil)
    redirect_to campaign_path(@campaign, anchor: "deeds"), notice: notice, alert: alert, status: :see_other
  end
end
