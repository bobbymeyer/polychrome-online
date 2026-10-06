# frozen_string_literal: true

# GM tool: put items in the party's chest or a character's bag, or correct a quantity.
class Campaigns::InventoriesController < ApplicationController
  include CampaignScoped

  before_action :set_campaign
  before_action :require_campaign_gm

  def create
    entry = params.expect(inventory: %i[item_id quantity character_id])
    item = @world.items.find(entry[:item_id])
    count = entry[:quantity].to_i.clamp(1, 99)
    holder = entry[:character_id].present? ? @campaign.characters.find(entry[:character_id]) : @campaign
    holder.add_item!(item, count)
    redirect_to campaign_prep_path(@campaign, anchor: "bag"), notice: "Added #{count} × #{item.name} to #{holder.bag_name}.", status: :see_other
  end

  def update
    row = @campaign.inventories.find(params[:id])
    row.update!(quantity: params.expect(inventory: [ :quantity ])[:quantity].to_i.clamp(0, 999))
    redirect_to campaign_prep_path(@campaign, anchor: "bag"), status: :see_other
  end
end
