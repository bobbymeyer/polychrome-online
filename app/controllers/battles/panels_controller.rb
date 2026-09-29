# frozen_string_literal: true

# The command panel: the per-seat part of the battle screen, served into a
# Turbo Frame. The shared board arrives by broadcast; this is what differs
# between the GM and each player.
class Battles::PanelsController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def show
    @battle.arrive!(current_seat.unit_id) if current_seat.unit_id # the first round's clock waits for everyone
    state = @battle.state
    @choosing = state["abilities"][params[:ability]] if params[:ability]
    @choosing = state.fetch("items", {})[params[:item]]&.merge("kind" => "item") if params[:item]
    @item_menu = params[:items].present?
    @trying = params[:custom].present?
    render layout: false
  end
end
