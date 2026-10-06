# frozen_string_literal: true

# The roads on a setting's atlas (WorldRoute).
class Worlds::RoutesController < ApplicationController
  include WorldScoped
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

  def edit
    @route = @world.world_routes.find(params[:id])
  end

  # The form, or from the atlas: a new bend where it was clicked ({ bend: { x, y } }),
  # or the bends as dragged ({ world_route: { waypoints: [...] } }).
  def update
    @route = @world.world_routes.find(params[:id])
    bend = params[:bend].presence || params.dig(:world_route, :bend).presence # JSON bodies are wrapped under world_route
    @route.bend_at(bend[:x].to_i, bend[:y].to_i) if bend
    raw = params.fetch(:world_route, {})
    fields = raw.permit(:state, :encounter_table_id, :travel_event, :duration).to_h
    fields["waypoints"] = Array(raw[:waypoints]).map { |pt| pt.respond_to?(:to_unsafe_h) ? pt.to_unsafe_h.values_at("x", "y") : Array(pt) } if raw.key?(:waypoints)
    fields["encounter_table"] = @world.encounter_tables.find_by(id: fields.delete("encounter_table_id")) if fields.key?("encounter_table_id")
    saved = @route.update(fields)
    return head(saved ? :no_content : :unprocessable_content) if request.format.json?

    if saved
      redirect_to world_world_places_path(@world, map: @route.from_place.world_map_id, anchor: "routes"), notice: "The road #{@route.label} saved.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    route = @world.world_routes.find(params[:id])
    route.destroy!
    redirect_to world_world_places_path(@world, anchor: "routes"), notice: "The road #{route.label} is gone.", status: :see_other
  end
end
