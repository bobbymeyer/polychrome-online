# frozen_string_literal: true

# Generating an image (docs/HANDOFF.md §8) for a book entry, or for one of a
# speaker's portraits. Starting a batch first saves the subject's own layer
# (its specifics, model and LoRAs), then queues the candidates with ComfyUI; the art
# section fills in as they land.
class ArtBatchesController < ApplicationController
  include ArtTargets

  before_action :set_world

  def create
    entry, subject = target
    return forbid unless can_generate?(entry)

    subject&.update!(params.fetch(:entry, {}).permit(:art_notes, :art_model, art_loras: {}))
    entry.location.set_mode_art!(entry.mode_key, params[:mode_art]) if entry.is_a?(ModeArt) && params.key?(:mode_art)
    # A speaker shows one strip at a time, whichever expression it is for.
    ArtBatch.where(entry: subject.portraits).destroy_all if entry.is_a?(Portrait)
    ArtBatch.where(entry: entry.location.mode_arts).destroy_all if entry.is_a?(ModeArt)
    transparent = { "1" => true, "0" => false }[params[:transparent]]
    ArtBatch.start!(entry, count: params[:count].presence || Comfy.config[:candidates], write: params[:write] != "0", transparent: transparent)
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

  # [what gets the image, whose layer the params edit (none for a mode: its
  # subject is the Gazetteer entry, edited in the book)]
  def target
    return [ art_mode, nil ] if mode_request?

    if speaker_request?
      owner = art_speaker
      expression = Portrait::EXPRESSIONS.include?(params[:expression]) ? params[:expression] : "neutral"
      [ owner.portraits.find_or_create_by!(expression: expression), owner ]
    else
      entry = art_entry
      [ entry, entry ]
    end
  end
end
