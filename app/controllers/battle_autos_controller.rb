# frozen_string_literal: true

# The GM puts a party member on auto for the rest of the battle, or takes
# them off it (BattleRecord#auto_fill!).
class BattleAutosController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def update
    return head :forbidden unless gm_seat?

    acted = @battle.battle_actions.count
    @battle.set_auto!(params.expect(:unit), params[:on] == "1")
    # If that played a beat, wait for it like any other action (§6).
    return render("panels/resolving", layout: false) if @battle.battle_actions.count > acted

    redirect_to battle_panel_path(@battle)
  end
end
