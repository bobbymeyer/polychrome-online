# frozen_string_literal: true

# Talk that points somewhere: a rumour can be about a place (hearing it puts
# the place on the map), an atlas place can come with the talk that leads
# to it, and a front's clock can come from a place (clearing it stops the
# clock).
class AddLeadsToRumoursAndPlaces < ActiveRecord::Migration[8.1]
  def change
    add_column :rumours, :about_id, :integer
    add_index :rumours, :about_id
    add_column :world_places, :lead, :text
    add_column :front_clocks, :source_id, :integer
    add_index :front_clocks, :source_id
  end
end
