# frozen_string_literal: true

# The art section alone (docs/HANDOFF.md §8), for the "art_panel" frame to
# reload as generated images land.
class ArtPanelsController < ApplicationController
  include ArtTargets

  before_action :set_world

  def show
    if speaker_request?
      render partial: "art_batches/portraits", locals: { owner: art_speaker }
    else
      render partial: "art_batches/studio", locals: { entry: art_entry }
    end
  end
end
