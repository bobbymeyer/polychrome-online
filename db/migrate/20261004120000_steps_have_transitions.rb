# frozen_string_literal: true

# How a change step comes on: a quick fade unless the GM says otherwise
# (a slow fade, a slide for a sprite, a cut). Lines and choices don't
# change the stage, so theirs goes unread.
class StepsHaveTransitions < ActiveRecord::Migration[8.1]
  def change
    add_column :beats, :transition, :string, null: false, default: "fade"
  end
end
