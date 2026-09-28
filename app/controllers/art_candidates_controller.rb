# frozen_string_literal: true

# Picking the winner (docs/HANDOFF.md §8): it becomes the entry's image, with
# its seed and the recipe that made it.
class ArtCandidatesController < ApplicationController
  def pick
    candidate = find_candidate
    entry = candidate.entry
    return forbid unless can_generate?(entry)

    candidate.pick!
    redirect_to entry_page(entry, anchor: "art"), notice: "#{entry.art_title.upcase_first} has a new image (seed #{entry.image_seed})."
  rescue Refusal => e
    redirect_to entry_page(entry, anchor: "art"), alert: e.message
  end

  # Make a draft properly (ArtBatch.refine!): full size and steps, from the draft.
  def refine
    candidate = find_candidate
    entry = candidate.entry
    return forbid unless can_generate?(entry)

    ArtBatch.refine!(candidate)
    redirect_to entry_page(entry, anchor: "art"), notice: "Making seed #{candidate.seed} properly."
  rescue Refusal => e
    redirect_to entry_page(entry, anchor: "art"), alert: e.message
  end

  private

  def find_candidate
    world = World.find_by!(slug: params[:world_slug])
    ArtCandidate.joins(:art_batch).where(art_batches: { world_id: world.id }).find(params[:id])
  end
end
