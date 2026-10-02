# frozen_string_literal: true

# A scene on the stage (Scene#start!): the GM puts it there, steps it beat
# by beat, lets it play on or pauses it, and takes it down.
class Scenes::PlaysController < ApplicationController
  before_action :set_scene
  before_action :require_campaign_gm

  def create
    @scene.start!
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  rescue Refusal, ActiveRecord::RecordInvalid => e
    redirect_back_or_to campaign_table_path(@campaign), alert: e.message, status: :see_other
  end

  # go: next | on | pause
  def update
    case params[:go]
    when "on" then @scene.play_on!
    when "pause" then @scene.pause!
    else @scene.advance!
    end
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  rescue Refusal, ActiveRecord::RecordInvalid => e
    redirect_back_or_to campaign_table_path(@campaign), alert: e.message, status: :see_other
  end

  def destroy
    @scene.stop!
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end

  private

  def set_scene
    @scene = Scene.find(params[:scene_id])
    @campaign = @scene.campaign
    @world = @campaign.world
  end
end
