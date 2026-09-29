# frozen_string_literal: true

# A cleared place's nearest town waits to welcome the party back
# (Campaign::Deeds), and stands them a night at the inn.
class AddWelcomesToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :welcomes, :json, default: {}, null: false
    add_column :campaigns, :free_rooms_node_id, :integer
  end
end
