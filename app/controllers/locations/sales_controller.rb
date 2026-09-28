# frozen_string_literal: true

# Selling to a town's shop for half the price: from the bag, or something a
# party member is wearing (only their player or the GM sells that).
class Locations::SalesController < ApplicationController
  include LocationScoped

  before_action :require_party_in_town

  def create
    if params[:slot]
      character = @campaign.characters.find(params.expect(:character_id))
      return forbid unless can_manage?(character)

      @campaign.sell_worn!(character, params.expect(:slot), at: @location, by: payer_name)
    else
      @campaign.sell!(@world.items.find_by!(slug: params.expect(:item)), params[:quantity], at: @location, by: payer_name)
    end
    back "Sold."
  end

  private

  def back_anchor = "shop"
end
