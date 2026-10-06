# frozen_string_literal: true

# A room's treasure, taken by the party: the GM hands it over, or anyone at
# the table picks it up in the room they're standing in.
class Locations::TreasuresController < ApplicationController
  include LocationScoped

  before_action :require_seat

  def create
    room = params.expect(:room)
    raise Refusal, "The party isn't in that room" unless table_gm? || @location.current_room_key == room

    line = @location.take_treasure!(room)
    params[:return_to] == "table" ? redirect_to(campaign_table_path(@campaign), notice: line, status: :see_other) : back(line)
  end

  private

  def require_seat
    head :forbidden unless table_seat(@campaign).seated?
  end
end
