# frozen_string_literal: true

# A world's page is the table of contents of its books.
class WorldsController < ApplicationController
  before_action :set_world, only: %i[show edit update]
  before_action :require_world_editor, only: %i[edit update]

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
    # Anyone can make a world, usually by copying one; it's theirs to edit.
    @world = World.new(params.expect(world: %i[name slug description]).merge(owner: current_user))
    source = World.find_by(slug: params[:copy_from]) if params[:copy_from].present?
    if @world.save
      if source
        @world.copy_books_from!(source)
        @world.copy_music_from!(source)
      end
      redirect_to @world, notice: source ? "#{@world.name} was created from #{source.name}'s books." : "#{@world.name} was created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    attrs = params.expect(world: [ :name, :description, *World::MUSIC.map { |scene| :"music_#{scene}" }, { remove_music: [] } ])
    # Removing a track and uploading its replacement in one go keeps the new one.
    removals = (Array(attrs.delete(:remove_music)) & World::MUSIC).reject { |scene| attrs[:"music_#{scene}"].present? }
    if @world.update(attrs)
      removals.each { |scene| @world.public_send(:"music_#{scene}").purge_later }
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
