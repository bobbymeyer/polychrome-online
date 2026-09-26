# frozen_string_literal: true

class SeatsController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def create
    seat = params.expect(:seat)
    if may_sit?(seat)
      character = seat_character(seat)
      character.update!(user: current_user) if character && character.user_id.nil?
      take_seat(seat)
    end
    redirect_to battle_panel_path(@battle)
  end

  def destroy
    leave_seat
    redirect_to battle_panel_path(@battle)
  end
end
