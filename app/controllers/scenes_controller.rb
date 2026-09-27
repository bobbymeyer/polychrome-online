# frozen_string_literal: true

# The GM's prepared scenes (Scene): written on the campaign page, played
# from the table.
class ScenesController < ApplicationController
  include CampaignScoped

  ENCOUNTER_SLOTS = 3

  before_action :set_campaign, only: %i[new create]
  before_action :set_scene, only: %i[edit update destroy play]
  before_action :require_campaign_gm

  def new
    @scene = @campaign.scenes.new
  end

  def create
    @scene = @campaign.scenes.new(scene_params)
    if @scene.save
      redirect_to campaign_path(@campaign, anchor: "scenes"), notice: "#{@scene.name} is ready to play.", status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @scene.update(scene_params)
      redirect_to campaign_path(@campaign, anchor: "scenes"), notice: "#{@scene.name} was updated.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @scene.destroy!
    redirect_to campaign_path(@campaign, anchor: "scenes"), notice: "#{@scene.name} was deleted.", status: :see_other
  end

  def play
    @scene.play!
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_back_or_to campaign_table_path(@campaign), alert: e.message, status: :see_other
  end

  private

  def set_scene
    @scene = Scene.find(params[:id])
    @campaign = @scene.campaign
    @world = @campaign.world
  end

  def scene_params
    raw = params.expect(scene: [ :name, :script, :ending, :map_node_id, :turn_choice, { encounter: [ %i[monster count] ] } ])
    encounter = JsonCasting.rows(raw.delete(:encounter)).each_with_object({}) do |row, counts|
      next if row["monster"].blank?

      counts[row["monster"]] = counts.fetch(row["monster"], 0) + row["count"].to_i.clamp(1, 9)
    end
    # A turn ending names a place and one of its turns ("12|burning"), or the
    # place going back to how it was ("12|").
    choice = raw.delete(:turn_choice)
    if raw[:ending] == "turn"
      node_id, key = choice.to_s.split("|", 2)
      raw = raw.merge(map_node_id: node_id, turn_key: key.to_s)
    end
    raw.merge(encounter: encounter)
  end
end
