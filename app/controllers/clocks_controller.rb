# frozen_string_literal: true

# The GM's clocks (Clock): made in prep or at the table, ticked by hand.
class ClocksController < ApplicationController
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

  # The mode to switch to comes as "location id|mode key", from one picker.
  def clock_params
    attrs = params.expect(clock: [ :name, :segments, :public, :full_line, :when_full, { triggers: [] } ])
    location_id, mode_key = attrs.delete(:when_full).to_s.split("|", 2)
    attrs.merge(location: location_id.presence && @campaign.locations.find_by(id: location_id), mode_key: mode_key)
  end

  def back(notice: nil, alert: nil)
    redirect_back_or_to campaign_path(@campaign, anchor: "clocks"), notice: notice, alert: alert, status: :see_other
  end
end
