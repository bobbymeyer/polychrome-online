# frozen_string_literal: true

# A player at the battle says they're ready: the first round's clock waits
# for everyone in the fight (BattleRecord#arrive!). Their Ready button goes;
# the countdown, for everyone, says who it's still waiting for.
class Battles::ArrivalsController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def create
    @battle.arrive!(current_seat.unit_id) if current_seat.unit_id
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("battle_ready") }
      format.html { redirect_to battle_path(@battle), status: :see_other }
    end
  end
end
