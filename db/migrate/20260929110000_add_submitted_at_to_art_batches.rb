# frozen_string_literal: true

# When a batch reached ComfyUI: its render timeout counts from there, not
# from when it was asked for (it may wait a while for ComfyUI to come back).
class AddSubmittedAtToArtBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :art_batches, :submitted_at, :datetime
  end
end
