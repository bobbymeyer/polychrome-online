# frozen_string_literal: true

# The GM's clocks (Clock): made in prep or at the table, ticked by hand.
class Campaigns::ClocksController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action :require_gm
  before_action :set_clock, only: %i[update destroy]

  def create
    clock = @campaign.clocks.new(clock_params)
    clock.save ? back(notice: "Clock “#{clock.name}” set.") : back(alert: clock.errors.full_messages.to_sentence)
  end

  def update
    @clock.update(clock_params) ? back(notice: "Clock “#{@clock.name}” saved.") : back(alert: @clock.errors.full_messages.to_sentence)
  end

  def destroy
    @clock.destroy!
    back notice: "Clock “#{@clock.name}” taken away."
  end

  private

  def require_gm
    head :forbidden unless table_gm?
  end

  def set_clock
    @clock = @campaign.clocks.find(params[:id])
  end

  # The mode it sets off when full, from one picker: one of the campaign's
  # places' modes, or nothing.
  def clock_params
    attrs = params.expect(clock: [ :name, :segments, :public, :full_line, :when_full, :map_node_id, { triggers: [], times: [] } ])
    mode_id = attrs.delete(:when_full).presence
    attrs.merge(location_mode: mode_id && LocationMode.joins(:location).where(locations: { campaign_id: @campaign.id }).find_by(id: mode_id))
  end

  def back(notice: nil, alert: nil)
    redirect_back_or_to campaign_prep_path(@campaign, anchor: "clocks"), notice: notice, alert: alert, status: :see_other
  end
end
