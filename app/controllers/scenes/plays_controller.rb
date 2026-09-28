# frozen_string_literal: true

# Playing a prepared scene at the table (Scene#play!).
class Scenes::PlaysController < ApplicationController
  before_action :set_scene
  before_action :require_campaign_gm

  def create
    @scene.play!
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  rescue Refusal, ActiveRecord::RecordInvalid => e
    redirect_back_or_to campaign_table_path(@campaign), alert: e.message, status: :see_other
  end

  private

  def set_scene
    @scene = Scene.find(params[:scene_id])
    @campaign = @scene.campaign
    @world = @campaign.world
  end
end
