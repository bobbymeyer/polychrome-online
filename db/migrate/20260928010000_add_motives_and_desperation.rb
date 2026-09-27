# frozen_string_literal: true

# Characters who are someone: why a character is here, in their own words,
# and each job's desperation move, found at the end of their rope.
class AddMotivesAndDesperation < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :motive, :string
    add_column :jobs, :desperation, :string
  end
end
