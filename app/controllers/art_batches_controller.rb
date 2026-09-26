# frozen_string_literal: true

# Generating an entry's image (docs/HANDOFF.md §8). Starting a batch first
# saves the entry's own layer (its specifics and LoRAs), then queues the
# candidates with ComfyUI; the page fills in as they land.
class ArtBatchesController < ApplicationController
  before_action :set_world

  def create
    entry = find_entry(params[:entry_type], params[:entry_slug])
    entry.update!(params.fetch(:entry, {}).permit(:art_notes, art_loras: {}))
    ArtBatch.start!(entry, count: params[:count].presence || Comfy.config[:candidates])
    redirect_to entry_page(entry, anchor: "art")
  end

  # Throw the candidates away.
  def destroy
    batch = @world.art_batches.find(params[:id])
    entry = batch.entry
    batch.destroy!
    redirect_to entry_page(entry, anchor: "art")
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end

  def find_entry(kind, slug)
    raise ActiveRecord::RecordNotFound unless ArtDirection::KINDS.include?(kind)

    @world.public_send(kind.pluralize).find_by!(slug: slug)
  end
end
