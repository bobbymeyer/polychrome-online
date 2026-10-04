# frozen_string_literal: true

# Generating an image (docs/HANDOFF.md §8) for a book entry, or for one of a
# speaker's portraits. Starting a batch first saves the subject's own layer
# (its specifics, model and LoRAs), then queues the candidates with ComfyUI; the art
# section fills in as they land.
class ArtBatchesController < ApplicationController
  include ArtTargets

  before_action :set_world

  rescue_from Refusal do |refusal|
    redirect_back_or_to root_path, alert: refusal.message, status: :see_other
  end

  def create
    entry, subject = target
    return forbid unless can_generate?(entry)

    if subject && params.key?(:entry)
      # A player writes their own character's specifics; the model and LoRAs are the GM's.
      allowed = subject.is_a?(ArtSubject) && !can_gm?(subject.campaign) ? [ :art_notes ] : [ :art_notes, :art_model, { art_loras: {} } ]
      allowed = [ :art_notes ] if subject.is_a?(MapSheet) && !subject.respond_to?(:art_model=)
      changes = params.fetch(:entry, {}).permit(*allowed)
      # A history-written figure whose looks the GM writes is theirs now.
      subject.update!(subject.has_attribute?(:edited) ? changes.merge(edited: true) : changes)
    end
    entry.mode.update!(art: params[:mode_art]) if entry.is_a?(ModeArt) && params.key?(:mode_art)
    entry.update!(art_notes: params[:beat_words]) if entry.is_a?(Beat) && params.key?(:beat_words)
    ArtBatch.where(entry: entry.location.mode_arts).destroy_all if entry.is_a?(ModeArt)
    ArtBatch.where(entry: entry.scene.beats).destroy_all if entry.is_a?(Beat) # one strip a scene
    options = { count: params[:count].presence || Comfy.config[:candidates], write: params[:write] != "0",
                transparent: { "1" => true, "0" => false }[params[:transparent]], draft: params[:draft] == "1" }
    if entry.is_a?(Portrait) && params[:every] == "1"
      # The chain's last link: every other expression, each redrawn from the Neutral portrait.
      (Portrait::EXPRESSIONS - [ "neutral" ]).each do |expression|
        ArtBatch.start!(subject.portraits.find_or_create_by!(expression: expression), **options.merge(draft: false), **chain_source(subject, expression))
      end
    else
      ArtBatch.start!(entry, **options, **(entry.is_a?(Portrait) ? chain_source(subject, entry.expression) : {}))
    end
    redirect_to entry_page(entry, anchor: "art")
  end

  # Throw the candidates away.
  def destroy
    batch = @world.art_batches.find(params[:id])
    entry = batch.entry
    return forbid unless can_generate?(entry)

    batch.destroy!
    redirect_to entry_page(entry, anchor: "art")
  end

  private

  # What a portrait is redrawn from, when asked (from: "sprite" | "neutral"):
  # the Neutral portrait from the sprite's head, any other expression from
  # the Neutral portrait. Nothing to start from: it starts blank.
  def chain_source(owner, expression)
    chain = Comfy.config.fetch(:chain, {})
    case params[:from]
    when "sprite"
      sprite = owner.sprite
      raise Refusal, "There's no sprite to draw the portrait from yet" unless sprite&.image&.attached?

      { source: { "kind" => "sprite", "id" => sprite.id }, denoise: chain.fetch(:portrait_denoise, 0.55) }
    when "neutral"
      neutral = owner.portraits.find_by(expression: "neutral")
      raise Refusal, "There's no Neutral portrait to draw from yet" unless neutral&.image&.attached? && expression != "neutral"

      { source: { "kind" => "portrait", "id" => neutral.id }, denoise: chain.fetch(:expression_denoise, 0.45) }
    else
      {}
    end
  end

  # [what gets the image, whose layer the params edit (none for a mode: its
  # subject is the Gazetteer entry, edited in the book)]
  def target
    return [ art_mode, nil ] if mode_request?
    return [ art_beat, nil ] if beat_request?
    return [ art_map, art_map ] if map_request? # its own specifics, model and LoRAs, like a book entry

    if sprite_request?
      owner = art_speaker
      [ owner.sprite || owner.create_sprite!, owner ]
    elsif speaker_request?
      owner = art_speaker
      expression = Portrait::EXPRESSIONS.include?(params[:expression]) ? params[:expression] : "neutral"
      [ owner.portraits.find_or_create_by!(expression: expression), owner ]
    else
      entry = art_entry
      [ entry, entry ]
    end
  end
end
