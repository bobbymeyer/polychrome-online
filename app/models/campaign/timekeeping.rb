# frozen_string_literal: true

# Time in a campaign: the day, and the part of it (dawn, day, dusk, night).
# A journey takes its road's time (none, for a step through a door); a rest
# sleeps until the next dawn, or through the morning if begun at dawn; the GM
# can pass time by hand. Each new day ticks the clocks that tick on dawn, so
# "the festival is in three days" is a three-segment clock, and the world
# moves on a little (Campaign::Overnight).
module Campaign::Timekeeping
  extend ActiveSupport::Concern

  TIMES = %w[dawn day dusk night].freeze

  included do
    validates :time_of_day, inclusion: { in: TIMES }
    validates :day, numericality: { only_integer: true, greater_than: 0 }
  end

  # "Moonsday, 12 Rainfall · dusk", or "Day 12 · dusk".
  def when_it_is
    "#{world.date(day)} · #{time_of_day}"
  end

  # Moves time on by parts of the day. Returns the number of new days.
  # announce: true says the time either way; :new_day only when a day starts.
  def pass_time!(parts = 1, announce: true)
    parts = parts.to_i.clamp(0, 400)
    return 0 if parts.zero?

    index = TIMES.index(time_of_day) + parts
    new_days = index / TIMES.size
    transaction do
      update!(day: day + new_days, time_of_day: TIMES[index % TIMES.size])
      if announce == true || (announce == :new_day && new_days.positive?)
        line = new_days.positive? ? "#{new_days > 1 ? "#{new_days} days pass. " : ''}#{world.date(day)}: #{time_of_day}." : "#{time_of_day.capitalize}."
        narrate(line)
      end
      follow_the_hours!
      new_days.times do
        tick_clocks!("dawn")
        overnight!
      end
      # Time spent somewhere is time to hear what people there are saying
      # (a new day hears it in #overnight!).
      hear_rumours! if new_days.zero?
    end
    new_days
  end

  # Places that are different by night (or any other part of the day)
  # become so, and stop being.
  def follow_the_hours!
    locations.where(id: LocationMode.where("json_array_length(times) > 0").select(:location_id)).find_each do |place|
      place.follow_the_hours!(time_of_day)
    end
  end

  # Parts of the day until the next dawn: none if it's dawn already.
  def until_dawn
    time_of_day == "dawn" ? 0 : TIMES.size - TIMES.index(time_of_day)
  end

  # How long a night's rest takes: until the next dawn, or, begun at dawn,
  # the morning (a rest never skips a whole day).
  def rest_time
    [ until_dawn, 1 ].max
  end
end
