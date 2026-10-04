# frozen_string_literal: true

# The GM's prepared scenes (Scene): written on the campaign page, played
# from the table.
class ScenesController < ApplicationController
  include CampaignScoped

  ENCOUNTER_SLOTS = 3

  before_action :set_campaign, only: %i[new create]
  before_action :set_scene, only: %i[edit update destroy]
  before_action :require_campaign_gm

  # A suggested scene (Drafts::Scene) arrives with its name and script.
  def new
    @scene = @campaign.scenes.new(params.fetch(:scene, {}).permit(:name, :script))
  end

  def create
    @scene = @campaign.scenes.new(scene_params)
    if @scene.save
      redirect_to edit_scene_path(@scene), notice: "#{@scene.name} is ready: build it step by step.", status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  # beat: the one the preview and the panel studio are on.
  def edit
    @beat = @scene.beats.find_by(id: params[:beat]) || @scene.beats.first
  end

  def update
    if @scene.update(scene_params)
      redirect_to edit_scene_path(@scene), notice: "#{@scene.name} was updated.", status: :see_other
    else
      @beat = @scene.beats.first
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @scene.destroy!
    redirect_to campaign_prep_path(@campaign, anchor: "scenes"), notice: "#{@scene.name} was deleted.", status: :see_other
  end

  private

  def set_scene
    @scene = Scene.find(params[:id])
    @campaign = @scene.campaign
    @world = @campaign.world
  end

  def scene_params
    raw = params.expect(scene: [ :name, :script, :ending, :map_node_id, :mode_choice, { encounter: [ %i[monster count] ] } ])
    encounter = JsonCasting.rows(raw.delete(:encounter)).each_with_object({}) do |row, counts|
      next if row["monster"].blank?

      counts[row["monster"]] = counts.fetch(row["monster"], 0) + row["count"].to_i.clamp(1, 9)
    end
    # A mode ending names a place and one of its modes ("12|7"), or the
    # place going back to how it was ("12|").
    choice = raw.delete(:mode_choice)
    if raw[:ending] == "mode"
      node_id, mode_id = choice.to_s.split("|", 2)
      node = @campaign.map_nodes.find_by(id: node_id)
      raw = raw.merge(map_node_id: node&.id, mode: mode_id.presence && node&.modes&.find_by(id: mode_id))
    end
    raw.merge(encounter: encounter)
  end
end
