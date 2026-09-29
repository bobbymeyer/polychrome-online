# frozen_string_literal: true

# The table's live panels, rendered again for everyone watching
# (Campaign#table_changed).
class TableRefreshJob < ApplicationJob
  discard_on ActiveJob::DeserializationError # the campaign is gone

  def perform(campaign)
    campaign.broadcast_table
  end
end
