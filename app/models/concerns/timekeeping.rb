# frozen_string_literal: true

# Time in a campaign: the day, and the part of it (dawn, day, dusk, night).
# A journey takes its road's time; a rest sleeps until the next dawn; the GM
# can pass time by hand. Each new day ticks the clocks that tick on dawn, so
# "the festival is in three days" is a three-segment clock.
module Timekeeping
  extend ActiveSupport::Concern

  TIMES = %w[dawn day dusk night].freeze

  included do
    validates :time_of_day, inclusion: { in: TIMES }
    validates :day, numericality: { only_integer: true, greater_than: 0 }
    after_update_commit :broadcast_time, if: -> { saved_change_to_day? || saved_change_to_time_of_day? }
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
      new_days.times { tick_clocks!("dawn") }
    end
    new_days
  end

  # Sleep until the next dawn.
  def until_dawn
    TIMES.size - TIMES.index(time_of_day)
  end

  private

  def broadcast_time
    %i[map map_gm].each { |stream| broadcast_replace_to self, stream, target: "table_time", partial: "tables/time", locals: { campaign: self } }
  end
end
