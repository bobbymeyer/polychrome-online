# frozen_string_literal: true

# The beats of a scene (Beat), written one by one in prep: the sequencer on
# the scene's page. Each beat is its own small form, saved as it changes.
class BeatsController < ApplicationController
  before_action :set_scene, only: :create
  before_action :set_beat, only: %i[update destroy]
  before_action :require_campaign_gm

  # A new beat after the one given (or last), empty but for a narrator's
  # line, ready to be written.
  def create
    after = @scene.beats.find_by(id: params[:after_id])
    beat = @scene.transaction do
      position = after ? after.position + 1 : @scene.beats.size
      @scene.beats.where("position >= ?", position).update_all("position = position + 1")
      @scene.beats.create!(position: position, text: params[:text].presence || "…")
    end
    redirect_to edit_scene_path(@scene, beat: beat.id, anchor: "beat_#{beat.id}"), status: :see_other
  end

  def update
    if @beat.update(beat_params)
      redirect_to edit_scene_path(@scene, beat: @beat.id, anchor: "beat_#{@beat.id}"), status: :see_other
    else
      redirect_to edit_scene_path(@scene, beat: @beat.id, anchor: "beat_#{@beat.id}"), alert: @beat.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    @scene.transaction do
      @beat.destroy!
      @scene.beats.reload.each_with_index { |beat, i| beat.update_columns(position: i) if beat.position != i }
    end
    redirect_to edit_scene_path(@scene), status: :see_other
  end

  private

  def set_scene
    @scene = Scene.find(params[:scene_id])
    @campaign = @scene.campaign
    @world = @campaign.world
  end

  def set_beat
    @beat = Beat.find(params[:id])
    @scene = @beat.scene
    @campaign = @scene.campaign
    @world = @campaign.world
  end

  # The speaker comes as "Npc:3", "Character:7" or "" (the narrator); a
  # choice as its "? A | B -> flag" text; who stands on the stage as rows.
  def beat_params
    raw = params.expect(beat: [ :speaker, :expression, :text, :backdrop, :map_node_id, :cue, :music, :art_notes, { figures: {} } ])
    attrs = raw.except(:speaker).to_h
    type, id = raw[:speaker].to_s.split(":", 2)
    attrs[:speaker] = Beat::SPEAKER_TYPES.include?(type) ? @campaign.public_send(type.underscore.pluralize).find_by(id: id) : nil
    attrs[:map_node_id] = nil unless attrs[:backdrop] == "place"
    if (choice = Beat.choice_from(attrs[:text]))
      attrs = attrs.merge(choice).merge(speaker: nil, expression: nil)
    else
      attrs = attrs.merge(kind: "say", options: [], flag_key: nil)
    end
    attrs
  end
end
