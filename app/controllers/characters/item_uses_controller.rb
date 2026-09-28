# frozen_string_literal: true

# Using an item from the party's bag outside battle, from a character's
# sheet: that character uses it, on themselves or another party member.
class Characters::ItemUsesController < ApplicationController
  include CampaignScoped

  before_action :set_character
  before_action :require_character_manager

  def create
    item = @world.items.find_by!(slug: params.expect(:item))
    target = @campaign.characters.find(params[:target_id].presence || @character.id)
    @campaign.use_item!(item, user: @character, target: target)
    redirect_to character_path(@character, anchor: "items"), notice: @campaign.messages.last.body, status: :see_other
  rescue Refusal => e
    sheet_error(e.message)
  end
end
