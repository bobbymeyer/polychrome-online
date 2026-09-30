# frozen_string_literal: true

# Things to do at a place (Pastime), one per line: an atlas place's are the
# setting's, a map place's the GM's own for the campaign.
class AddActivitiesToPlaces < ActiveRecord::Migration[8.1]
  def change
    add_column :world_places, :activities, :text
    add_column :map_nodes, :activities, :text
  end
end
