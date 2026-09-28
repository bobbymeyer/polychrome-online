# frozen_string_literal: true

# Field abilities at the table (FieldUse): a player asks as their own
# character (or the GM for anyone), and the GM approves or vetoes.
class Campaigns::FieldUsesController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def create
    seat = table_seat
    character = seat == "gm" ? @campaign.characters.find(params[:character_id]) : seat
    return forbid("Sit as your character to use their field ability.") unless character.is_a?(Character)

    FieldUse.request!(character)
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end

  def update
    return forbid("Only the GM says yes or no.") unless table_seat == "gm"

    use = @campaign.field_uses.find(params[:id])
    if params[:verdict] == "veto"
      use.veto!(params[:line])
    else
      use.approve!(difficulty: params[:difficulty].presence || use.ability.field_difficulty)
    end
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
