# frozen_string_literal: true

# Someone has the battle open (battle_watch_controller, now and then): its
# clock keeps running, or starts again if it held (BattleRecord#watch!).
class Battles::WatchesController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def update
    @battle.watch!
    head :no_content
  end
end
