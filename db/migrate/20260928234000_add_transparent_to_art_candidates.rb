# frozen_string_literal: true

# Whether a candidate that should have lost its background really did,
# read off the image itself.
class AddTransparentToArtCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :art_candidates, :transparent, :boolean
  end
end
