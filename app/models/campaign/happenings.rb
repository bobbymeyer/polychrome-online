# frozen_string_literal: true

# What sets things off, in one place. Something happens in the campaign
# (the party rests, travels or fails a check; a part of the day passes; a
# day begins) and #happen! does everything that listens for it:
#
#   rest          the day's work pays off (Campaign::Payoffs); rest clocks;
#                 what happens at camp or the inn goes to the GM (Remarks)
#   travel        journey clocks; what happens on the road goes to the GM
#   failed_check  failed-check clocks
#   hours         places change with the calendar (a mode with times); what
#                 people are saying where the party is (unless a day began)
#   dawn          new-day clocks; the world moves on overnight
#                 (Campaign::Overnight), which ticks the now-and-then clocks
#   arrive        the party gets somewhere (at:): whoever is from there is
#                 home, and ties to people there come up (Campaign::Belonging);
#                 the world's arrival line that fits best goes to the GM
#                 (Campaign::Remarks), and maybe a sign of a clock's latest
#                 step; the visit is counted (Campaign::Moment)
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
  # bed: whether a rest was in a bed (rest).
  def happen!(event, day: self.day, period: self.period, was: nil, new_day: false, at: nil, bed: false)
    case event
    when "arrive"
      arrive_among_their_own!(at)
      offer_arrival_line!(at)
      offer_sign!(at)
      count_visit!(at)
    when "rest"
      payday!
      tick_clocks!("rest", day: day, period: period)
      offer_event!("rest", bed: bed)
    when "hours"
      follow_the_hours!(*was)
      # Time spent somewhere is time to hear what people there are saying
      # (a new day hears it overnight).
      hear_rumours! unless new_day
    when "dawn"
      tick_clocks!("dawn", day: day, period: period)
      overnight!
    when "travel"
      tick_clocks!("travel", day: day, period: period)
      offer_event!("travel")
    else
      tick_clocks!(event, day: day, period: period)
    end
  end

  # The running clock a hard move ticks (Outcome "tick"): one at the
  # party's place if there is one, else the one nearest to full.
  def clock_to_tick
    clocks.running.to_a.min_by { |clock| [ clock.map_node_id == current_node_id ? 0 : 1, -clock.filled.fdiv(clock.segments), clock.id ] }
  end

  private

  # Every running clock that listens for this, and keeps to the calendar
  # now, goes on a segment.
  def tick_clocks!(event, day: self.day, period: self.period)
    clocks.running.order(:id).select { |clock| clock.ticks_on?(event, almanac, day, period) }
          .each { |clock| clock.tick!(1, reason: EVENTS[event]) }
  end
end
