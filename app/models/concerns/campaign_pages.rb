# frozen_string_literal: true

# Something shown on a campaign's documents (the campaign page, prep,
# legends): when it changes, they refresh (Campaign::Broadcasts).
module CampaignPages
  extend ActiveSupport::Concern

  included do
    broadcasts_refreshes_to ->(record) { [ record.campaign, :pages ] }
  end
end
