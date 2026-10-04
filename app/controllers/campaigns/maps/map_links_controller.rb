# frozen_string_literal: true

# A map put beside another, by direction (MapLink): "to is <direction> of from".
class Campaigns::Maps::MapLinksController < ApplicationController
  include CampaignScoped
  include MapGm

  before_action :set_campaign, :require_table_gm

  def create
    from = @campaign.maps.find(params[:map_id])
    link = @campaign.map_links.new(from_map: from, to_map: @campaign.maps.find_by(id: params.dig(:map_link, :to_map_id)), direction: params.dig(:map_link, :direction))
    if link.save
      redirect_to campaign_maps_path(@campaign, map: from.id), notice: "#{link.to_map.name} is #{MapSheet::COMPASS.fetch(link.direction).downcase} of #{from.name}.", status: :see_other
    else
      redirect_to campaign_maps_path(@campaign, map: from.id), alert: link.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    link = @campaign.map_links.find(params[:id])
    link.destroy!
    redirect_to campaign_maps_path(@campaign, map: params[:map_id]), notice: "#{link.to_map.name} and #{link.from_map.name} are no longer side by side.", status: :see_other
  end
end
