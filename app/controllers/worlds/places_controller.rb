# frozen_string_literal: true

# A setting's atlas (WorldPlace, WorldRoute): its places and roads, written
# once for every campaign in the world. Its editors write it; its GMs read it.
class Worlds::PlacesController < ApplicationController
  before_action :set_world
  before_action :require_lore, only: :index
  before_action :require_world_editor, except: :index
  before_action :set_place, only: %i[edit update destroy]

  def index
    @places = @world.world_places.in_order.includes(:location_template)
    @routes = @world.world_routes.includes(:from_place, :to_place, :encounter_table)
    @maps = @world.world_maps.in_order.includes(:parent)
    @map = @world.world_maps.find_by(id: params[:map]) || @world.root_map
    @scope = MapScope.new(@world, use: :editor, gm: true)
  end

  # From a click on the atlas (x, y on a map), or the "New place" button.
  def new
    map = @world.world_maps.find_by(id: params[:world_map_id])
    @place = @world.world_places.new(kind: "town", known: true, world_map: map,
                                     x: (params[:x].presence || MapNode::WIDTH / 2).to_i.clamp(0, MapNode::WIDTH),
                                     y: (params[:y].presence || MapNode::HEIGHT / 2).to_i.clamp(0, MapNode::HEIGHT))
  end

  def create
    @place = @world.world_places.new(place_params)
    @place.save ? redirect_to(world_world_places_path(@world), notice: "#{@place.name} is on the atlas.") : render(:new, status: :unprocessable_content)
  end

  def edit; end

  # Also takes { x, y } (or the map) alone from dragging on the atlas (a fetch, not the form).
  def update
    saved = @place.update(place_params)
    return head(saved ? :no_content : :unprocessable_content) if request.format.json?

    saved ? redirect_to(world_world_places_path(@world, map: @place.world_map_id), notice: "#{@place.name} saved.") : render(:edit, status: :unprocessable_content)
  end

  def destroy
    @place.destroy!
    redirect_to world_world_places_path(@world), notice: "#{@place.name} is off the atlas. Campaigns keep their own.", status: :see_other
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end


  def set_place
    @place = @world.world_places.find(params[:id])
  end

  def place_params
    fields = params.expect(world_place: [ :name, :kind, :x, :y, :known, :description, :notes, :lead, :location_template_id, :activities, :night_line,
                                          :world_map_id, { past_form: WorldPlace.new.past_form.keys } ])
    fields = fields.merge(location_template: fields[:location_template_id].presence && @world.location_templates.find_by(id: fields[:location_template_id])).except(:location_template_id) if fields.key?(:location_template_id)
    fields = fields.merge(world_map: @world.world_maps.find_by(id: fields[:world_map_id]) || @world.root_map).except(:world_map_id) if fields.key?(:world_map_id)
    fields
  end
end
