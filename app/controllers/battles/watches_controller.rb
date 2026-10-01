# frozen_string_literal: true

# Someone has the battle open (heartbeat_controller, now and then): its
# clock keeps running, or starts again if it held (BattleRecord#watch!).
class Battles::WatchesController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def update
    @battle.watch!
    current_seat.character&.seen!
    head :no_content
  end
end
