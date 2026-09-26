# frozen_string_literal: true

# Who is sitting at a campaign's table: "gm", a character, or nobody.
#
# There are no accounts yet, so a seat is a choice remembered in the
# session, and anyone can take any seat. What it controls is real, though:
# the server decides who a message is from, and only a seat's own streams
# (the table, plus the GM's or that character's whispers) are signed for its
# page.
module TableSeat
  extend ActiveSupport::Concern

  included do
    helper_method :table_seat, :table_gm?
  end

  private

  # "gm", a Character of this campaign, or nil.
  def table_seat(campaign = @campaign)
    seat = session.dig(:table_seats, campaign.id.to_s)
    return "gm" if seat == "gm"

    campaign.characters.find_by(id: seat) if seat.present?
  end

  def table_gm?(campaign = @campaign)
    table_seat(campaign) == "gm"
  end

  def take_table_seat(campaign, seat)
    session[:table_seats] = (session[:table_seats] || {}).merge(campaign.id.to_s => seat.to_s)
  end

  def leave_table_seat(campaign)
    session[:table_seats]&.delete(campaign.id.to_s)
  end
end
