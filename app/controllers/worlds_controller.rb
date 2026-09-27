# frozen_string_literal: true

# A world's page is the table of contents of its books.
class WorldsController < ApplicationController
  before_action :require_admin, except: %i[index show]
  before_action :set_world, only: %i[show edit update]

  # Home: your campaigns first (the ones you play in or GM), then the rest
  # to join, then the worlds and their books.
  def index
    @worlds = World.order(:name)
    campaigns = Campaign.includes(:world, :gm, characters: :user).order(updated_at: :desc)
    @my_campaigns, @other_campaigns = campaigns.partition do |c|
      c.gm_id == current_user.id || c.characters.any? { |ch| ch.user_id == current_user.id }
    end
  end

  def show; end

  def new
    @world = World.new
  end

  def edit; end

  def create
    @world = World.new(params.expect(world: %i[name slug description]))
    source = World.find_by(slug: params[:copy_from]) if params[:copy_from].present?
    if @world.save
      @world.copy_books_from!(source) if source
      redirect_to @world, notice: source ? "#{@world.name} was created from #{source.name}'s books." : "#{@world.name} was created."
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
