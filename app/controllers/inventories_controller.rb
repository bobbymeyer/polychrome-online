# frozen_string_literal: true

# GM tool: put items in the party bag, or correct a quantity.
class InventoriesController < ApplicationController
  include CampaignScoped

  before_action :set_campaign

  def create
    entry = params.expect(inventory: %i[item_id quantity])
    item = @world.items.find(entry[:item_id])
    count = entry[:quantity].to_i.clamp(1, 99)
    @campaign.add_item!(item, count)
    redirect_to campaign_path(@campaign), notice: "Added #{count} × #{item.name}.", status: :see_other
  end

  def update
    row = @campaign.inventories.find(params[:id])
    row.update!(quantity: params.expect(inventory: [ :quantity ])[:quantity].to_i.clamp(0, 999))
    redirect_to campaign_path(@campaign), status: :see_other
  end
end
