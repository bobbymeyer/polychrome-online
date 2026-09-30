# frozen_string_literal: true

# A town's thanks is its reputation (a deed there), not free rooms: one
# price rule for everything a town sells (Location::Town#price_here).
class RemoveFreeRoomsFromCampaigns < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    remove_column :campaigns, :free_rooms_node_id, :integer
  end
end
