# frozen_string_literal: true

# The roads on a setting's atlas (WorldRoute).
class WorldRoutesController < ApplicationController
  before_action :set_world
  before_action :require_world_editor

  def create
    fields = params.expect(world_route: %i[from_place_id to_place_id state encounter_table_id travel_event duration])
    route = @world.world_routes.new(
      from_place: @world.world_places.find_by(id: fields[:from_place_id]), to_place: @world.world_places.find_by(id: fields[:to_place_id]),
      state: fields[:state], travel_event: fields[:travel_event].presence, duration: fields[:duration].presence || 1,
      encounter_table: fields[:encounter_table_id].presence && @world.encounter_tables.find_by(id: fields[:encounter_table_id])
    )
    if route.save
      redirect_to world_world_places_path(@world, anchor: "routes"), notice: "A road from #{route.label}.", status: :see_other
    else
      redirect_to world_world_places_path(@world, anchor: "routes"), alert: route.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    route = @world.world_routes.find(params[:id])
    route.destroy!
    redirect_to world_world_places_path(@world, anchor: "routes"), notice: "The road #{route.label} is gone.", status: :see_other
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end
end
