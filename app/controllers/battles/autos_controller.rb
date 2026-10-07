# frozen_string_literal: true

# Auto for the rest of the battle (BattleRecord#auto_fill!): the GM for any
# party member, a player for their own, so they can talk and let the fight
# run. Picking a command yourself takes you off it again.
class Battles::AutosController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def update
    unit = params.expect(:unit)
    return head :forbidden unless gm_seat? || seat_unit&.id == unit

    acted = @battle.battle_actions.count
    @battle.set_auto!(unit, params[:on] == "1")
    # If that played a beat, wait for it like any other action (§6).
    return render("battles/panels/resolving", layout: false) if @battle.battle_actions.count > acted

    redirect_to battle_panel_path(@battle)
  end
end
