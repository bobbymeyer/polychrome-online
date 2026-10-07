# frozen_string_literal: true

# The command panel: the per-seat part of the battle screen, served into a
# Turbo Frame. The shared board arrives by broadcast; this is what differs
# between the GM and each player.
class Battles::PanelsController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def show
    field = @battle.field
    @choosing = field.ability(params[:ability]) if params[:ability]
    @choosing = field.items[params[:item]]&.merge("kind" => "item") if params[:item]
    @item_menu = params[:items].present?
    @trying = params[:custom].present?
    render layout: false
  end
end
