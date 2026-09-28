# frozen_string_literal: true

# Loads a town or dungeon (and its campaign and world) for the controllers
# nested under it, and says a refusal back on its page. Its GM controls are
# the GM's at the table; its shop and services are for whoever is in town.
module LocationScoped
  extend ActiveSupport::Concern

  included do
    include TableSeat

    before_action :set_location

    rescue_from Refusal do |refusal|
      back alert: refusal.message
    end
  end

  private

  def set_location
    @location = Location.find(params[:location_id] || params[:id])
    @campaign = @location.campaign
    @world = @campaign.world
  end

  def require_gm
    head :forbidden unless table_gm?
  end

  # Only in the town where the party is (the GM shops anywhere).
  def require_party_in_town
    forbid(away_message) unless helpers.may_shop?(@location)
  end

  def away_message = "You can only shop in the town where the party is."

  # Who's paying: the player's character, or the GM by name.
  def payer_name
    table_seat(@campaign).character&.name || current_user.name
  end

  def back(notice = nil, alert: nil, anchor: back_anchor)
    redirect_to location_path(@location, anchor: anchor), notice: notice, alert: alert, status: :see_other
  end

  # Where on the page to come back to.
  def back_anchor = nil
end
