# frozen_string_literal: true

# Buying from a town's shop with the party's money. Players shop where the
# party is; the GM shops anywhere.
class Locations::PurchasesController < ApplicationController
  include LocationScoped

  before_action :require_party_in_town

  def create
    @campaign.buy!(@world.items.find_by!(slug: params.expect(:item)), params[:quantity], at: @location, by: payer_name)
    back "Bought."
  end

  private

  def back_anchor = "shop"
end
