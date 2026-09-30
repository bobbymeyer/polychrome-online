# frozen_string_literal: true

# Who is sitting at a campaign's table (Seat): the GM, a character, or
# nobody.
#
# A seat is a choice remembered in the session, but only a seat the account
# may take counts (User#can_gm?, #can_play?), checked on every request: the
# GM seat is the campaign's GM's (or an admin's), a character's seat its
# player's. Sitting in a character nobody owns yet makes it yours. The server
# decides who a message is from, and only a seat's own streams (the table,
# plus the GM's or that character's whispers) are signed for its page.
module TableSeat
  extend ActiveSupport::Concern

  included do
    helper_method :table_seat, :table_gm?
  end

  private

  # The Seat this account has at the campaign's table. With no seat chosen
  # yet, the obvious one: the GM seat if it's your campaign, otherwise your
  # only character here.
  def table_seat(campaign = @campaign)
    (@table_seats ||= {})[campaign.id] ||= find_table_seat(campaign)
  end

  def find_table_seat(campaign)
    seat = session.dig(:table_seats, seat_key(campaign))
    return default_table_seat(campaign) if seat.nil?
    return Seat.nobody if seat == "" # stood up on purpose
    return (can_gm?(campaign) ? Seat.gm : Seat.nobody) if seat == "gm"

    character = campaign.characters.find_by(id: seat)
    character && can_play?(character) ? Seat.of(character) : Seat.nobody
  end

  # Seats belong to the account, not the browser: two people signing in on
  # one browser never share a seat.
  def seat_key(record)
    "#{current_user&.id}:#{record.id}"
  end

  def default_table_seat(campaign)
    return Seat.nobody unless current_user
    return Seat.gm if campaign.gm_id == current_user.id

    mine = campaign.characters.where(user: current_user).limit(2).to_a
    mine.one? ? Seat.of(mine.first) : Seat.nobody
  end

  # Take a seat if this account may. Returns whether it did.
  def claim_table_seat(campaign, seat)
    if seat.to_s == "gm"
      return false unless can_gm?(campaign)
    else
      character = campaign.characters.find_by(id: seat)
      return false unless character && can_play?(character)

      character.update!(user: current_user) if character.user_id.nil?
    end
    take_table_seat(campaign, seat)
    true
  end

  def table_gm?(campaign = @campaign)
    table_seat(campaign).gm?
  end

  # The GM's controls at a campaign's table: only the GM seat may.
  #   before_action :require_table_gm
  def require_table_gm
    head :forbidden unless table_gm?
  end

  def take_table_seat(campaign, seat)
    @table_seats = nil
    session[:table_seats] = (session[:table_seats] || {}).merge(seat_key(campaign) => seat.to_s)
  end

  # Recorded as an empty seat (not deleted) so the obvious seat doesn't
  # silently take over again.
  def leave_table_seat(campaign)
    @table_seats = nil
    session[:table_seats] = (session[:table_seats] || {}).merge(seat_key(campaign) => "")
  end
end
