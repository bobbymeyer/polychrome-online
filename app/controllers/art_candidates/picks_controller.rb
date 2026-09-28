# frozen_string_literal: true

# Picking the winner (docs/HANDOFF.md §8): it becomes the entry's image, with
# its seed and the recipe that made it.
class ArtCandidates::PicksController < ApplicationController
  include ArtCandidateScoped

  def create
    @candidate.pick!
    redirect_to entry_page(@entry, anchor: "art"), notice: "#{@entry.art_title.upcase_first} has a new image (seed #{@entry.image_seed})."
  end
end
