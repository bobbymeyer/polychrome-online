# frozen_string_literal: true

# A character takes items out of the party's chest, or puts their own in
# (their player, or the GM).
class Characters::ChestsController < ApplicationController
  include CampaignScoped

  before_action :set_character
  before_action :require_character_manager

  def update
    item = @world.items.find(params.expect(:item_id))
    count = params[:quantity].to_i.clamp(1, 99)
    if params.expect(:direction) == "take"
      @character.take_from_chest!(item, count)
      notice = "#{@character.name} takes #{count} × #{item.name} from the chest."
    else
      @character.put_in_chest!(item, count)
      notice = "#{@character.name} puts #{count} × #{item.name} in the chest."
    end
    redirect_to character_path(@character, anchor: "chest"), notice: notice, status: :see_other
  end
end
