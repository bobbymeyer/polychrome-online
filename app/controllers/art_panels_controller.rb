# frozen_string_literal: true

# The art section alone (docs/HANDOFF.md §8), for the "art_panel" frame to
# reload as generated images land.
class ArtPanelsController < ApplicationController
  include ArtTargets

  before_action :set_world

  def show
    if mode_request?
      art = art_mode
      return head :forbidden unless can_gm?(art.location.campaign)

      render partial: "art_batches/mode_art", locals: { location: art.location, chosen: art.mode_key }
    elsif speaker_request?
      owner = art_speaker
      return head :forbidden unless can_gm?(owner.campaign)

      render partial: "art_batches/portraits", locals: { owner: owner }
    else
      return head :forbidden unless admin?

      render partial: "art_batches/studio", locals: { entry: art_entry }
    end
  end
end
