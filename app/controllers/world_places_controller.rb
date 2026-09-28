# frozen_string_literal: true

# A setting's atlas (WorldPlace, WorldRoute): its places and roads, written
# once for every campaign in the world. Its editors write it; its GMs read it.
class WorldPlacesController < ApplicationController
  before_action :set_world
  before_action :require_lore, only: :index
  before_action :require_world_editor, except: :index
  before_action :set_place, only: %i[edit update destroy]

  def index
    @places = @world.world_places.in_order.includes(:location_template)
    @routes = @world.world_routes.includes(:from_place, :to_place, :encounter_table)
  end

  def new
    @place = @world.world_places.new(kind: "town", x: MapNode::WIDTH / 2, y: MapNode::HEIGHT / 2, known: true)
  end

  def create
    @place = @world.world_places.new(place_params)
    @place.save ? redirect_to(world_world_places_path(@world), notice: "#{@place.name} is on the atlas.") : render(:new, status: :unprocessable_content)
  end

  def edit; end

  def update
    @place.update(place_params) ? redirect_to(world_world_places_path(@world), notice: "#{@place.name} saved.") : render(:edit, status: :unprocessable_content)
  end

  def destroy
    @place.destroy!
    redirect_to world_world_places_path(@world), notice: "#{@place.name} is off the atlas. Campaigns keep their own.", status: :see_other
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end

  def require_lore
    forbid unless knows_the_lore?
  end

  def set_place
    @place = @world.world_places.find(params[:id])
  end

  def place_params
    fields = params.expect(world_place: %i[name kind x y known description notes location_template_id])
    fields.merge(location_template: fields[:location_template_id].presence && @world.location_templates.find_by(id: fields[:location_template_id]))
          .except(:location_template_id)
  end
end
