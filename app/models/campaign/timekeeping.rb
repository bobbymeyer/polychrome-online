# frozen_string_literal: true

# Time in a campaign: the day, and the part of it, in the setting's calendar
# (World#almanac: dawn, day, dusk and night, unless the world says
# otherwise). A journey takes its road's time (none, for a step through a
# door); a rest sleeps until the day begins again, or through its first part
# if begun then; the GM can pass time by hand. Each new day ticks the clocks that tick on dawn, so
# "the festival is in three days" is a three-segment clock, and the world
# moves on a little (Campaign::Overnight).
module Campaign::Timekeeping
  extend ActiveSupport::Concern

  included do
    # A new campaign begins at the start of the setting's day.
    before_validation(on: :create) { self.time_of_day = almanac.periods.first if world && !almanac.period(time_of_day) }
    validates :day, numericality: { only_integer: true, greater_than: 0 }
    validate(if: :will_save_change_to_time_of_day?) do
      errors.add(:time_of_day, "isn't a part of the day in #{world.name}") if world && !almanac.period(time_of_day)
    end
  end

  def almanac = world.almanac

  # The part of the day, as the calendar names it now (the first, if the
  # setting has since renamed them).
  def period = almanac.period(time_of_day) || almanac.periods.first

  def dark? = almanac.dark?(period)

  # The light, whatever the setting calls the part of the day: "dawn" for
  # its first, "night" in its dark, "dusk" just before, else "day". The
  # date card wears its colour.
  def daylight
    index = almanac.period_index(period)
    return "night" if dark?
    return "dawn" if index.zero?

    almanac.dark?(almanac.periods[(index + 1) % almanac.periods.size]) ? "dusk" : "day"
  end

  # "Moonsday, 12 Rainfall · dusk", or "Day 12 · dusk".
  def when_it_is
    "#{world.date(day)} · #{period}"
  end

  # Moves time on by parts of the day. Returns the number of new days.
  # announce: true says the time either way; :new_day only when a day starts.
  def pass_time!(parts = 1, announce: true)
    parts = parts.to_i.clamp(0, 400)
    return 0 if parts.zero?

    was = [ day, period ]
    now, new_days = almanac.later(period, parts)
    transaction do
      update!(day: day + new_days, time_of_day: now)
      if announce == true || (announce == :new_day && new_days.positive?)
        line = new_days.positive? ? "#{new_days > 1 ? "#{new_days} days pass. " : ''}#{world.date(day)}: #{period}." : "#{period.upcase_first}."
        narrate(line)
      end
      happen!("hours", was: was, new_day: new_days.positive?)
      # Each day that began, in turn (a clock kept to Mondays ticks on the Monday).
      new_days.times { |i| happen!("dawn", day: was.first + i + 1, period: almanac.periods.first) }
    end
    new_days
  end

  # Places that are different by night, or in winter, or on a market day
  # (a mode with times: MapNode#follow_the_hours!), become so and stop
  # being. Where the party is, the table hears it.
  def follow_the_hours!(was_day, was_period)
    map_nodes.where(id: Mode.where("json_array_length(times) > 0").select(:map_node_id)).includes(:modes, :current_mode, :location).find_each do |place|
      place.follow_the_hours!(was_day, was_period, quiet: place == @arriving)
    end
  end

  # How it is at a place the party has just reached: what the modes it's in say.
  def how_it_is_here!(node)
    node.modes_on.each { |mode| narrate(mode.line || "#{node.name}: #{mode.name}.") }
  end

  # Parts of the day until the day begins again: none if it just has.
  def until_the_day_begins
    index = almanac.period_index(period)
    index.zero? ? 0 : almanac.periods.size - index
  end

  # How long a night's rest takes: until the day begins, or, begun then,
  # its first part (a rest never skips a whole day).
  def rest_time
    [ until_the_day_begins, 1 ].max
  end
end
