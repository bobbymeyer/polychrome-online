# frozen_string_literal: true

# The table's controls (Campaign::Controls): what kind of moment the GM has
# called, so everyone sees the actions that fit it and no others. "talk" is
# the floor; "travel" shows the ways on; "doing" what there is to do here.
class TheTableHasControls < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :controls, :string, null: false, default: "talk"
  end
end
