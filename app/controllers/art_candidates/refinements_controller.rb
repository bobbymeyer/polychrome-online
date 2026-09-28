# frozen_string_literal: true

# Making a draft properly (ArtBatch.refine!): full size and steps, from the
# draft itself.
class ArtCandidates::RefinementsController < ApplicationController
  include ArtCandidateScoped

  def create
    ArtBatch.refine!(@candidate)
    redirect_to entry_page(@entry, anchor: "art"), notice: "Making seed #{@candidate.seed} properly."
  end
end
