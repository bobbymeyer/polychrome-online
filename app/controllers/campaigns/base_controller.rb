# frozen_string_literal: true

# Everything that belongs to one campaign (app/controllers/campaigns/):
# the campaign is loaded for every action, and a controller says which GM
# it needs on top (TableSeat: the seat's, for the table's controls;
# Authorization#require_campaign_gm: the account's, for Prep).
class Campaigns::BaseController < ApplicationController
  include CampaignScoped

  before_action :set_campaign
end
