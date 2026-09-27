# frozen_string_literal: true

# A town's services, paid from the party's purse (Campaign#use_service!):
# a room at the inn, a raising at the temple, a rumour at the guild. A
# player pays for their own character; the GM for anyone. Like shopping,
# only in the town where the party is.
class ServicesController < ApplicationController
  include TableSeat

  before_action :set_location
  before_action :require_customer

  rescue_from ArgumentError do |error|
    redirect_to location_path(@location, anchor: anchor), alert: error.message, status: :see_other
  end

  def create
    if params[:everyone].present?
      @campaign.rest_at_inn!(at: @location, by: customer_name)
    else
      character = @campaign.characters.find(params.expect(:character_id))
      return forbid("#{character.name} isn't yours to pay for.") unless can_manage?(character)

      @campaign.use_service!(params.expect(:kind), character, at: @location, by: customer_name)
    end
    redirect_to location_path(@location, anchor: anchor), status: :see_other
  end

  private

  def set_location
    @location = Location.find(params[:location_id])
    @campaign = @location.campaign
    @world = @campaign.world
  end

  def anchor
    "service-#{params[:kind] || 'inn'}"
  end

  def require_customer
    forbid("Services are for the town where the party is.") unless helpers.may_shop?(@location)
  end

  def customer_name
    seat = table_seat(@campaign)
    seat.is_a?(Character) ? seat.name : current_user.name
  end
end
