# frozen_string_literal: true

# Jobs that feel like themselves: a signature command, always on the menu
# while in the job, and a passive, kept in every job once it's mastered.
class AddSignaturesAndPassivesToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :jobs, :signature, :string
    add_column :jobs, :passive, :string
  end
end
