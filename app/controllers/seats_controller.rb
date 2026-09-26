# frozen_string_literal: true

class SeatsController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def create
    seat = params.expect(:seat)
    take_seat(seat) if seat == "gm" || @battle.unit(seat)&.dig("side") == "party"
    redirect_to battle_panel_path(@battle)
  end

  def destroy
    leave_seat
    redirect_to battle_panel_path(@battle)
  end
end
