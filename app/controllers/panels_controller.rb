# frozen_string_literal: true

# The command panel: the per-seat part of the battle screen, served into a
# Turbo Frame. The shared board arrives by broadcast; this is what differs
# between the GM and each player.
class PanelsController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def show
    @choosing = @battle.state["abilities"][params[:ability]] if params[:ability]
    render layout: false
  end
end
