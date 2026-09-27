# frozen_string_literal: true

# A town's shop: buy from its stock with party gil, sell from the bag for
# half the price. Players shop where the party is; the GM shops anywhere.
class ShopsController < ApplicationController
  include TableSeat

  before_action :set_location
  before_action :require_shopper

  rescue_from ArgumentError do |error|
    redirect_to location_path(@location, anchor: "shop"), alert: error.message, status: :see_other
  end

  def buy
    @campaign.buy!(item, params[:quantity], at: @location, by: shopper_name)
    redirect_to location_path(@location, anchor: "shop"), notice: "Bought.", status: :see_other
  end

  def sell
    @campaign.sell!(item, params[:quantity], at: @location, by: shopper_name)
    redirect_to location_path(@location, anchor: "shop"), notice: "Sold.", status: :see_other
  end

  # Something a party member is wearing: only their player or the GM sells it.
  def sell_worn
    character = @campaign.characters.find(params.expect(:character_id))
    return forbid unless can_manage?(character)

    @campaign.sell_worn!(character, params.expect(:slot), at: @location, by: shopper_name)
    redirect_to location_path(@location, anchor: "shop"), notice: "Sold.", status: :see_other
  end

  private

  def set_location
    @location = Location.find(params[:location_id])
    @campaign = @location.campaign
    @world = @campaign.world
  end

  def item
    @world.items.find_by!(slug: params.expect(:item))
  end

  def require_shopper
    forbid("You can only shop in the town where the party is.") unless helpers.may_shop?(@location)
  end

  def shopper_name
    seat = table_seat(@campaign)
    seat.is_a?(Character) ? seat.name : current_user.name
  end
end
