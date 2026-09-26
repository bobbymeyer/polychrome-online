# frozen_string_literal: true

# Who is sitting at a campaign's table: "gm", a character, or nobody.
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

  # "gm", a Character of this campaign, or nil. With no seat chosen yet, the
  # obvious one: your only character here, or the GM seat if it's your
  # campaign and you play nobody in it.
  def table_seat(campaign = @campaign)
    seat = session.dig(:table_seats, seat_key(campaign))
    return default_table_seat(campaign) if seat.nil?
    return nil if seat == "" # stood up on purpose
    return (can_gm?(campaign) ? "gm" : nil) if seat == "gm"

    character = campaign.characters.find_by(id: seat)
    character if character && can_play?(character)
  end

  # Seats belong to the account, not the browser: two people signing in on
  # one browser never share a seat.
  def seat_key(record)
    "#{current_user&.id}:#{record.id}"
  end

  def default_table_seat(campaign)
    return nil unless current_user

    mine = campaign.characters.where(user: current_user).limit(2).to_a
    return mine.first if mine.one?

    "gm" if mine.empty? && campaign.gm_id == current_user.id
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
    table_seat(campaign) == "gm"
  end

  def take_table_seat(campaign, seat)
    session[:table_seats] = (session[:table_seats] || {}).merge(seat_key(campaign) => seat.to_s)
  end

  # Recorded as an empty seat (not deleted) so the obvious seat doesn't
  # silently take over again.
  def leave_table_seat(campaign)
    session[:table_seats] = (session[:table_seats] || {}).merge(seat_key(campaign) => "")
  end
end
