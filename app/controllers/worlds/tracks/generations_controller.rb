# frozen_string_literal: true

# Make a generated track (again) in ComfyUI with ACE-Step (TrackJob): the
# book's page follows along as it lands.
class Worlds::Tracks::GenerationsController < ApplicationController
  before_action :set_world
  before_action :require_world_editor

  def create
    track = @world.tracks.find(params[:track_id])
    track.generate!
    redirect_to world_tracks_path(@world), notice: "ComfyUI is making #{track.name}.", status: :see_other
  rescue Refusal => e
    redirect_to world_tracks_path(@world), alert: e.message, status: :see_other
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end
end
