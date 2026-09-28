# frozen_string_literal: true

# A setting's fronts (WorldFront): its pressures, as clocks and secrets,
# written once and dealt into campaigns. Its editors write them; its GMs
# read them.
class WorldFrontsController < ApplicationController
  before_action :set_world
  before_action :require_lore, only: :index
  before_action :require_world_editor, except: :index
  before_action :set_front, only: %i[edit update destroy]

  def index
    @fronts = @world.world_fronts.in_order
  end

  def new
    @front = @world.world_fronts.new
  end

  def create
    @front = @world.world_fronts.new(front_params)
    @front.save ? redirect_to(world_world_fronts_path(@world), notice: "#{@front.name} is ready to deal in.") : render(:new, status: :unprocessable_content)
  end

  def edit; end

  def update
    @front.update(front_params) ? redirect_to(world_world_fronts_path(@world), notice: "#{@front.name} saved.") : render(:edit, status: :unprocessable_content)
  end

  def destroy
    @front.destroy!
    redirect_to world_world_fronts_path(@world), notice: "#{@front.name} is gone. Campaigns keep what was dealt in.", status: :see_other
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end

  def require_lore
    forbid unless knows_the_lore?
  end

  def set_front
    @front = @world.world_fronts.find(params[:id])
  end

  def front_params
    params.expect(world_front: [ :name, :description,
                                 { clocks: [ [ :name, :segments, :full_line, :public, :place_id, :mode_name, :mode_line, :mode_description, { triggers: [] } ] ],
                                   secrets: [ %i[body place_id figure_id] ] } ]).to_h
  end
end
