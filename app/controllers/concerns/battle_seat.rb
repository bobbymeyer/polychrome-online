# frozen_string_literal: true

# Who is sitting where at a battle: "gm", a party unit id, or nobody.
#
# There are no accounts yet, so a seat is just a choice remembered in the
# session. Anyone can take any seat; this decides which controls a browser
# sees, not who is allowed to see them.
module BattleSeat
  extend ActiveSupport::Concern

  included do
    helper_method :current_seat, :gm_seat?, :seat_unit
  end

  private

  def set_battle
    @battle = BattleRecord.find(params[:battle_id] || params[:id])
    @world = @battle.world
  end

  def current_seat
    seat = session.dig(:seats, @battle.id.to_s)
    seat if seat == "gm" || @battle.unit(seat)&.dig("side") == "party"
  end

  def take_seat(seat)
    session[:seats] = (session[:seats] || {}).merge(@battle.id.to_s => seat)
  end

  def leave_seat
    session[:seats]&.delete(@battle.id.to_s)
  end

  def gm_seat?
    current_seat == "gm"
  end

  def seat_unit
    @battle.unit(current_seat) unless gm_seat?
  end
end
