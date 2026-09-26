# frozen_string_literal: true

# Every GM diff on a campaign's generated locations (§7), in one place.
class ChangesController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def show
    return head :forbidden unless table_gm?

    @locations = @campaign.locations.includes(:location_template, :map_node).order(:id)
  end
end
