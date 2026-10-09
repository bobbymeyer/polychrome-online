# frozen_string_literal: true

# A trap waiting in a room (Location::Exploration): the GM has someone try
# to disarm it (a check, with the skill or stat they pick), or lets it go off.
class Locations::TrapsController < ApplicationController
  include LocationScoped

  before_action :require_table_gm

  def create
    room = params.expect(:room)
    if params[:verdict] == "disarm"
      character = @campaign.characters.find(params.expect(:character_id))
      @location.disarm_trap!(room, character: character, stat: params.expect(:stat), difficulty: params[:difficulty].presence || "normal")
    else
      @location.spring_trap!(room)
    end
    back
  end
end
