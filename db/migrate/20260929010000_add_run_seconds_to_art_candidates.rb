# frozen_string_literal: true

# How long ComfyUI spent on each candidate, from its own history.
class AddRunSecondsToArtCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :art_candidates, :run_seconds, :float
  end
end
