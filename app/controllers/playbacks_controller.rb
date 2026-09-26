# frozen_string_literal: true

# GM fast-forward (§6): sets the playback speed for every viewer.
class PlaybacksController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def update
    return head :forbidden unless gm_seat?

    speed = params.expect(:speed).to_i
    @battle.set_speed!(speed) if BattleRecord::SPEEDS.include?(speed)
    redirect_to battle_panel_path(@battle)
  end
end
