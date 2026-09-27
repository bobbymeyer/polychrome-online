# frozen_string_literal: true

# Who is sitting where at a battle: "gm", a party unit id, or nobody.
#
# A seat is a choice remembered in the session, checked against the account
# on every request: the GM seat is the campaign's GM's (a campaign-less
# battle's is an admin's), and a party unit's seat its character's player's.
# Without a battle seat, the seat at the campaign's table carries over: the
# GM stays GM, and a character's player controls that character's unit.
module BattleSeat
  extend ActiveSupport::Concern
  include TableSeat

  included do
    helper_method :current_seat, :gm_seat?, :seat_unit, :battle_gm?, :may_sit?
  end

  private

  def set_battle
    @battle = BattleRecord.find(params[:battle_id] || params[:id])
    @world = @battle.world
  end

  def current_seat
    seat = session.dig(:seats, seat_key(@battle)) || seat_from_table
    seat if may_sit?(seat)
  end

  def may_sit?(seat)
    return battle_gm? if seat == "gm"
    return false unless @battle.unit(seat)&.dig("side") == "party"

    character = seat_character(seat)
    character.nil? || can_play?(character)
  end

  def battle_gm?
    @battle.campaign ? can_gm?(@battle.campaign) : admin?
  end

  # The campaign character a party unit stands for, if any.
  def seat_character(unit_id)
    @battle.campaign&.characters&.find { |c| c.battle_unit_id == unit_id }
  end

  def seat_from_table
    return unless @battle.campaign

    seat = table_seat(@battle.campaign)
    seat == "gm" ? "gm" : seat&.battle_unit_id
  end

  def take_seat(seat)
    session[:seats] = (session[:seats] || {}).merge(seat_key(@battle) => seat)
  end

  # Recorded as an empty seat (not deleted) so the table seat doesn't
  # silently take over again.
  def leave_seat
    session[:seats] = (session[:seats] || {}).merge(seat_key(@battle) => "")
  end

  def gm_seat?
    current_seat == "gm"
  end

  def seat_unit
    @battle.unit(current_seat) unless gm_seat?
  end
end
