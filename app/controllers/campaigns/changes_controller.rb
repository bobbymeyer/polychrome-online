# frozen_string_literal: true

# Every GM diff on a campaign's generated locations (§7), in one place.
class Campaigns::ChangesController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action :require_table_gm

  def show
    @locations = @campaign.locations.includes(:location_template, :map_node).order(:id)
  end
end
