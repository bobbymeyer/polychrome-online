# frozen_string_literal: true

# A clock as a danger (docs/STORY.md, item 8): what it wants, and a step a
# little worse for each segment, each with signs the party might see on the
# way (Portent). Written on a front's clock in the setting, and copied to
# the campaign's clock when the front is dealt in.
class ClocksCarryImpulsesAndPortents < ActiveRecord::Migration[8.1]
  def change
    add_column :clocks, :impulse, :string
    add_column :clocks, :portents, :text
    add_column :front_clocks, :impulse, :string
    add_column :front_clocks, :portents, :text
  end
end
