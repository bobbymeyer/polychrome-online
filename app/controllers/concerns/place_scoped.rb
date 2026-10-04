# frozen_string_literal: true

# Loads a place on the map (and its campaign and world) for the GM's
# controls nested under it, and goes back to where the GM works on it: its
# town or dungeon's page, or else the map.
module PlaceScoped
  extend ActiveSupport::Concern

  included do
    include TableSeat

    before_action :set_node
    before_action :require_table_gm

    rescue_from Refusal do |refusal|
      back alert: refusal.message
    end
  end

  private

  def set_node
    @node = MapNode.find(params[:map_node_id])
    @campaign = @node.campaign
    @world = @campaign.world
  end


  def back(notice = nil, alert: nil)
    place = @node.location ? location_path(@node.location) : campaign_maps_path(@campaign, map: @node.map_id)
    redirect_to place, notice: notice, alert: alert, status: :see_other
  end
end
