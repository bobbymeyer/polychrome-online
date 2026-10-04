# frozen_string_literal: true

# A beat doubled, right after itself: the same stage, the next line.
class Beats::CopiesController < ApplicationController
  before_action :set_beat
  before_action :require_campaign_gm

  def create
    copy = @scene.transaction do
      @scene.beats.where("position > ?", @beat.position).update_all("position = position + 1")
      @scene.beats.create!(@beat.attributes.slice("kind", "speaker_type", "speaker_id", "expression", "text", "backdrop", "map_node_id",
                                                  "figures", "cue", "music", "options", "flag_key", "action", "fx").merge("position" => @beat.position + 1))
    end
    redirect_to edit_scene_path(@scene, beat: copy.id, anchor: "beat_#{copy.id}"), status: :see_other
  end

  private

  def set_beat
    @beat = Beat.find(params[:beat_id])
    @scene = @beat.scene
    @campaign = @scene.campaign
    @world = @campaign.world
  end
end
