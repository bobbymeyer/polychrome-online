# frozen_string_literal: true

# What sets things off, in one place. Something happens in the campaign
# (the party rests, travels or fails a check; a part of the day passes; a
# day begins) and #happen! does everything that listens for it:
#
#   rest          the day's work pays off (Campaign::Payoffs); rest clocks
#   travel        journey clocks
#   failed_check  failed-check clocks
#   hours         places change with the calendar (a mode with times); what
#                 people are saying where the party is (unless a day began)
#   dawn          new-day clocks; the world moves on overnight
#                 (Campaign::Overnight), which ticks the now-and-then clocks
#   arrive        the party gets somewhere (at:): whoever is from there is
#                 home, and ties to people there come up (Campaign::Belonging)
#
# A clock listens for events (Clock#triggers), and can keep to the
# calendar's words as modes and things to do do ("each new day, on
# Mondays": Clock#times). Nothing else calls these listeners directly.
module Campaign::Happenings
  extend ActiveSupport::Concern

  # Each event, as the table hears it ticked a clock.
  EVENTS = {
    "rest" => "the party rested", "travel" => "time on the road", "failed_check" => "a failed check",
    "hours" => "time passing", "dawn" => "a new day", "now_and_then" => "time passing"
  }.freeze

  # day, period: when it happened (a day that began in a long wait, not
  # the last one). was: [day, period] before time passed (hours).
  # new_day: whether the hours that passed began a day (hours).
  # at: where the party got to (arrive).
  def happen!(event, day: self.day, period: self.period, was: nil, new_day: false, at: nil)
    case event
    when "arrive"
      arrive_among_their_own!(at)
    when "rest"
      payday!
      tick_clocks!("rest", day: day, period: period)
    when "hours"
      follow_the_hours!(*was)
      # Time spent somewhere is time to hear what people there are saying
      # (a new day hears it overnight).
      hear_rumours! unless new_day
    when "dawn"
      tick_clocks!("dawn", day: day, period: period)
      overnight!
    else
      tick_clocks!(event, day: day, period: period)
    end
  end

  private

  # Every running clock that listens for this, and keeps to the calendar
  # now, goes on a segment.
  def tick_clocks!(event, day: self.day, period: self.period)
    clocks.running.order(:id).select { |clock| clock.ticks_on?(event, almanac, day, period) }
          .each { |clock| clock.tick!(1, reason: EVENTS[event]) }
  end
end
