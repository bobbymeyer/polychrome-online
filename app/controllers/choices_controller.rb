# frozen_string_literal: true

# A choice for the table (Message kind "choice"): players pick, as their
# own character, and the GM settles it.
class ChoicesController < ApplicationController
  include TableSeat

  before_action :set_choice

  def pick
    seat = table_seat
    return forbid("Sit as your character to pick.") unless seat.is_a?(Character)

    pick = @choice.picks.find_or_initialize_by(character: seat)
    pick.option = params[:option]
    pick.save ? head(:no_content) : forbid(pick.errors.full_messages.to_sentence)
  end

  def settle
    return forbid("Only the GM settles a choice.") unless table_seat == "gm"

    @choice.settle!(params[:option])
    head :no_content
  rescue ArgumentError => e
    forbid(e.message)
  end

  private

  def set_choice
    @choice = Message.where(kind: "choice").find(params[:id])
    @campaign = @choice.campaign
    @world = @campaign.world
  end
end
