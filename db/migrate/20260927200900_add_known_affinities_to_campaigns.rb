# What the party has learned about each monster, by hitting it or scanning
# it: { "goblin" => { "fire" => "weak", "ice" => "none", "sleep" => "immune" } }.
class AddKnownAffinitiesToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :known_affinities, :json, null: false, default: {}
  end
end
