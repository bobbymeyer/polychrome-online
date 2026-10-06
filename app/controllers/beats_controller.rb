# frozen_string_literal: true

# The steps of a scene (Beat), written one by one in prep: the sequencer on
# the scene's page. Each step is its own small form, saved as it changes.
class BeatsController < ApplicationController
  include CampaignScoped

  # What a new step of each kind starts as.
  STARTS = {
    "say" => { "text" => "…" }, "choice" => { "options" => [ "Yes", "No" ] }, "backdrop" => { "backdrop" => "black" },
    "sprite" => { "action" => "enter" }, "music" => { "music" => "follow" }, "fx" => { "fx" => "fade" }
  }.freeze
  before_action :set_scene, only: :create
  before_action :set_beat, only: %i[update destroy]
  before_action :require_campaign_gm

  # A new step of a kind, after the one given (or last), ready to be written.
  def create
    kind = STARTS.key?(params[:kind].to_s) ? params[:kind].to_s : "say"
    after = @scene.beats.find_by(id: params[:after_id])
    beat = @scene.transaction do
      position = after ? after.position + 1 : @scene.beats.size
      @scene.beats.where("position >= ?", position).update_all("position = position + 1")
      attrs = STARTS[kind].merge("kind" => kind, "position" => position)
      if kind == "sprite"
        someone = @campaign.npcs.order(:name).first || @campaign.characters.order(:created_at).first
        attrs["figures"] = [ { "type" => someone.class.name, "id" => someone.id, "side" => "left", "expression" => "neutral" } ] if someone
      end
      @scene.beats.create!(attrs)
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

  # Each kind takes its own fields. A line's speaker comes as "Npc:3",
  # "Character:7" or "" (the narrator), and a line written as "? A | B ->
  # flag" is a choice (and a choice rewritten without the ? a line); a
  # sprite step's someone as "Npc:3" too.
  def beat_params
    raw = params.expect(beat: [ :speaker, :expression, :text, :backdrop, :map_node_id, :cue, :music, :image, :who, :side, :action, :fx, :transition ])
    case @beat.kind
    when "say", "choice"
      attrs = raw.slice(:expression, :text, :cue).to_h
      attrs[:speaker] = person(raw[:speaker])
      if (choice = Beat.choice_from(attrs[:text]))
        attrs.merge(choice).merge(speaker: nil, expression: nil, cue: nil)
      else
        attrs.merge(kind: "say", options: [], flag_key: nil)
      end
    when "backdrop"
      attrs = raw.slice(:backdrop, :map_node_id, :image, :transition).to_h
      attrs[:map_node_id] = nil unless attrs[:backdrop] == "place"
      attrs.delete(:image) if attrs[:image].blank? # the panel stays unless another is uploaded
      attrs
    when "sprite"
      who = person(raw[:who])
      { action: raw[:action], transition: raw[:transition], figures: (who ? [ { type: who.class.name, id: who.id, side: raw[:side], expression: raw[:expression] } ] : []) }
    when "music" then raw.slice(:music, :transition).to_h
    when "fx" then raw.slice(:fx).to_h
    end
  end

  def person(key)
    type, id = key.to_s.split(":", 2)
    Beat::SPEAKER_TYPES.include?(type) ? @campaign.public_send(type.underscore.pluralize).find_by(id: id) : nil
  end
end
