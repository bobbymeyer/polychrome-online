# frozen_string_literal: true

# Calling off a battle nobody will finish (BattleRecord#call_off!).
class Battles::CallOffsController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def create
    return forbid unless battle_gm?

    @battle.call_off!
    redirect_back_or_to battle_path(@battle), notice: "#{@battle.name} was called off.", status: :see_other
  end
end
