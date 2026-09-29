# frozen_string_literal: true

# A player's battle page, connected and listening, says they're here: the
# first round's clock waits for everyone (BattleRecord#arrive!). Sent once
# by the page (arrival_controller.js), never by loading it.
class Battles::ArrivalsController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def create
    @battle.arrive!(current_seat.unit_id) if current_seat.unit_id
    head :no_content
  end
end
