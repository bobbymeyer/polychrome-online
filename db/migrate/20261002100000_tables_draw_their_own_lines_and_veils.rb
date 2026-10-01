# frozen_string_literal: true

# A table's own lines and veils, beside its world's (Campaign::Limits): one
# per line, as they were added, with nobody's name on them.
class TablesDrawTheirOwnLinesAndVeils < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :lines, :text
    add_column :campaigns, :veils, :text
  end
end
