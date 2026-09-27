# frozen_string_literal: true

# Jobs are story rewards: a campaign opens with the jobs its GM picks and
# grants the rest as the story goes. Nil means every job is open (how
# campaigns ran before).
class AddOpenJobsToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :open_jobs, :json
  end
end
