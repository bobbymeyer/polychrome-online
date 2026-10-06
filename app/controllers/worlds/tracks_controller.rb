# frozen_string_literal: true

# A world's Music book (Track): what each kind of scene plays, and the
# tracks the GM calls by name from the stage. Anyone who can see the world
# can read it; its editors change it. A track is uploaded or linked
# (YouTube, Spotify).
class Worlds::TracksController < ApplicationController
  include WorldScoped
  before_action :require_world_editor, except: :index
  before_action :set_track, only: %i[edit update destroy]

  def index
    @tracks = @world.tracks.in_order.with_attached_audio
  end

  def new
    @track = @world.tracks.new(source: params[:source].presence_in(Track::SOURCES) || "upload")
  end

  def create
    @track = @world.tracks.new(track_params)
    if @track.save
      redirect_to world_tracks_path(@world), notice: "#{@track.name} is in the book.", status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @track.update(track_params)
      redirect_to world_tracks_path(@world), notice: "#{@track.name} saved.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @track.destroy!
    redirect_to world_tracks_path(@world), notice: "#{@track.name} is out of the book.", status: :see_other
  end

  private

  def set_track
    @track = @world.tracks.find(params[:id])
  end

  def track_params
    params.expect(track: %i[name scene source url audio position])
  end
end
