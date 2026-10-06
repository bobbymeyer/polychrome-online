# frozen_string_literal: true

# The GM's prep for a campaign, apart from the campaign page: scenes to
# play, clocks and fronts, secrets, the party's deeds and what's being
# said, and flags. It and its forms are the GM's account's, seated or not (TableSeat).
class Campaigns::PrepsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action :require_campaign_gm

  def show; end
end
