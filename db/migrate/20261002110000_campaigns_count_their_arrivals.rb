# frozen_string_literal: true

# How many times the party has arrived at each place on the map, so a story
# row can tell a first visit from a homecoming (Campaign::Moment).
class CampaignsCountTheirArrivals < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :visits, :json, default: {}, null: false
  end
end
