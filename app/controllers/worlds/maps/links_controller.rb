# frozen_string_literal: true

# A setting's map put beside another, by direction (WorldMapLink).
class Worlds::Maps::LinksController < ApplicationController
  before_action :set_world
  before_action :require_world_editor

  def create
    from = @world.world_maps.find(params[:world_map_id])
    link = @world.world_map_links.new(from_map: from, to_map: @world.world_maps.find_by(id: params.dig(:world_map_link, :to_map_id)),
                                      direction: params.dig(:world_map_link, :direction))
    if link.save
      redirect_to world_world_places_path(@world, map: from.id), notice: "#{link.to_map.name} is #{MapSheet::COMPASS.fetch(link.direction).downcase} of #{from.name}.", status: :see_other
    else
      redirect_to world_world_places_path(@world, map: from.id), alert: link.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    link = @world.world_map_links.find(params[:id])
    link.destroy!
    redirect_to world_world_places_path(@world, map: params[:world_map_id]), notice: "#{link.to_map.name} and #{link.from_map.name} are no longer side by side.", status: :see_other
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end
end
