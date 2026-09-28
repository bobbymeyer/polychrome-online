# frozen_string_literal: true

# Loads one of a world's generated candidates (ArtCandidate) and the entry
# it's for, which the person must be able to generate art for.
module ArtCandidateScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_candidate

    rescue_from Refusal do |refusal|
      redirect_to entry_page(@entry, anchor: "art"), alert: refusal.message
    end
  end

  private

  def set_candidate
    world = World.find_by!(slug: params[:world_slug])
    @candidate = ArtCandidate.joins(:art_batch).where(art_batches: { world_id: world.id }).find(params[:art_candidate_id])
    @entry = @candidate.entry
    forbid unless can_generate?(@entry)
  end
end
