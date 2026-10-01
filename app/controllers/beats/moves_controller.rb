# frozen_string_literal: true

# A beat changes places with the one before or after it (the sequencer).
class Beats::MovesController < ApplicationController
  before_action :set_beat
  before_action :require_campaign_gm

  def create
    step = params[:direction] == "up" ? -1 : 1
    other = @scene.beats.find_by(position: @beat.position + step)
    if other
      @scene.transaction do
        other.update_columns(position: @beat.position)
        @beat.update_columns(position: @beat.position + step)
      end
    end
    redirect_to edit_scene_path(@scene, beat: @beat.id, anchor: "beat_#{@beat.id}"), status: :see_other
  end

  private

  def set_beat
    @beat = Beat.find(params[:beat_id])
    @scene = @beat.scene
    @campaign = @scene.campaign
    @world = @campaign.world
  end
end
