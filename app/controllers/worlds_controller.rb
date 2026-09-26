# frozen_string_literal: true

# A world's page is the table of contents of its books.
class WorldsController < ApplicationController
  before_action :require_admin, except: %i[index show]
  before_action :set_world, only: %i[show edit update]

  def index
    @worlds = World.order(:name)
  end

  def show; end

  def new
    @world = World.new
  end

  def edit; end

  def create
    @world = World.new(params.expect(world: %i[name slug description]))
    if @world.save
      redirect_to @world, notice: "#{@world.name} was created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @world.update(params.expect(world: %i[name description]))
      redirect_to @world, notice: "#{@world.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:slug])
  end
end
