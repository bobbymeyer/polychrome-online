# frozen_string_literal: true

# A setting's maps (WorldMap; docs/HANDOFF.md §7, "Maps"): the atlas page
# edits the one open (?map=); making, changing (a form, or x, y alone from
# dragging on the parent map) and removing them is the world's editors'.
class Worlds::MapsController < ApplicationController
  include WorldScoped
  before_action :require_world_editor
  before_action :set_map, only: %i[edit update destroy]

  def create
    map = @world.world_maps.new(map_params.reverse_merge(parent_id: params[:parent_id].presence))
    if map.save
      redirect_to world_world_places_path(@world, map: map.id), notice: "#{map.name} is a map now.", status: :see_other
    else
      redirect_to world_world_places_path(@world, map: params[:parent_id]), alert: map.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def edit
    redirect_to world_world_places_path(@world, map: @map.id)
  end

  def update
    @map.image.purge_later if params.dig(:world_map, :remove_image) == "1"
    saved = @map.update(map_params)
    return head(saved ? :no_content : :unprocessable_content) if request.format.json?

    if saved
      redirect_to world_world_places_path(@world, map: @map.id), notice: "#{@map.name} saved.", status: :see_other
    else
      redirect_to world_world_places_path(@world, map: @map.id), alert: @map.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    if @world.world_maps.count <= 1
      return redirect_to world_world_places_path(@world, map: @map.id), alert: "The atlas needs one map at least.", status: :see_other
    end

    @map.destroy!
    redirect_to world_world_places_path(@world), notice: "#{@map.name} is off the atlas. Campaigns keep theirs.", status: :see_other
  end

  private

  def set_map
    @map = @world.world_maps.find(params[:id])
  end

  def map_params
    fields = params.expect(world_map: [ :name, :parent_id, :x, :y, :description, :image ])
    fields[:parent_id] = fields[:parent_id].presence && @world.world_maps.find_by(id: fields[:parent_id])&.id if fields.key?(:parent_id)
    fields.compact_blank.merge(fields.slice(:parent_id, :description))
  end
end
