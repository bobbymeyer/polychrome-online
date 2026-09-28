# frozen_string_literal: true

# A setting's cast (WorldFigure): its people, written once, brought into
# each campaign as NPCs. Its editors write it; its GMs read it.
class WorldFiguresController < ApplicationController
  include PortraitUploads

  before_action :set_world
  before_action :require_lore, only: :index
  before_action :require_world_editor, except: :index
  before_action :set_figure, only: %i[edit update destroy]

  def index
    @figures = @world.world_figures.in_order.includes(:world_place, :monster)
  end

  def new
    @figure = @world.world_figures.new
  end

  def create
    @figure = @world.world_figures.new(figure_params)
    if @figure.save
      @figure.update_portraits!(**portrait_params)
      redirect_to world_world_figures_path(@world), notice: "#{@figure.name} joins the cast.", status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @figure.update(figure_params)
      @figure.update_portraits!(**portrait_params)
      redirect_to world_world_figures_path(@world), notice: "#{@figure.name} saved.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @figure.destroy!
    redirect_to world_world_figures_path(@world), notice: "#{@figure.name} leaves the cast. Campaigns keep their own.", status: :see_other
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end

  def require_lore
    forbid unless knows_the_lore?
  end

  def set_figure
    @figure = @world.world_figures.find(params[:id])
  end

  def figure_params
    fields = params.expect(world_figure: %i[name title blurb description art_notes colour monster_id world_place_id])
    fields.merge(monster: fields[:monster_id].presence && @world.monsters.find_by(id: fields[:monster_id]),
                 world_place: fields[:world_place_id].presence && @world.world_places.find_by(id: fields[:world_place_id]))
          .except(:monster_id, :world_place_id)
  end
end
