# frozen_string_literal: true

# Something to do at a place that takes part of a day: go to class, work a
# shift, see someone, go down into the other world at night. A place lists
# them one per line, the way scenes are written:
#
#   Attend class (morning, after school, 2): The bell. Maths, then lunch.
#   Swim at the lido (summer, weekend): Chlorine and shrieking.
#   Visit the shrine: Incense, and the sound of the sea.
#   The Undertow (late night, 2)
#
# In brackets: when it can be done, in the setting's calendar words (parts
# of the day, days of the week, months, seasons: Pointcrawl::Calendar#on?;
# any time, if none are given), and how many parts of the day it takes
# (one, if not given). After the colon, what the table hears when the party
# does it. The table picks one like a way on (Campaign::Ways): a vote,
# settled by the GM, and time passes.
Pastime = Data.define(:name, :times, :takes, :line)

class Pastime
  # A colon only ends the name when a space follows it: "Wait for the 0:13 (night)".
  FORMAT = /\A(?<name>(?:[^():]|:(?!\s))+?)\s*(?:\((?<when>[^)]*)\))?\s*(?::\s+(?<line>.*)|:)?\z/

  # [pastimes, problems] from a place's text, read by a world's calendar.
  def self.parse(text, almanac = Pointcrawl::Calendar.new)
    problems = []
    pastimes = text.to_s.lines.map(&:strip).reject(&:empty?).filter_map do |raw|
      match = FORMAT.match(raw)
      unless match
        problems << "“#{raw.truncate(40)}” needs a name before any brackets or colon"
        next
      end

      times = []
      takes = 1
      most = almanac.periods.size
      match[:when].to_s.split(%r{\s*[/,]\s*}).map(&:strip).reject(&:empty?).each do |word|
        if word.match?(/\A\d+\z/) then takes = word.to_i
        elsif (kind = almanac.kind_of(word)) then times << almanac.words[kind].find { |name| name.casecmp?(word) }
        elsif word.downcase != "any" then problems << "“#{match[:name]}”: #{word} isn't in the calendar (a part of the day, a day of the week, a month or a season) or a number of parts"
        end
      end
      problems << "“#{match[:name]}” takes 1 to #{most} parts of the day" unless takes.between?(1, most)
      new(name: match[:name].strip, times: times, takes: takes.clamp(1, most), line: match[:line].to_s.strip.presence)
    end
    dupes = pastimes.map(&:name).tally.select { |_, n| n > 1 }.keys
    problems << "#{dupes.to_sentence} is listed twice" if dupes.any?
    [ pastimes, problems ]
  end

  def self.list(text, almanac = Pointcrawl::Calendar.new) = parse(text, almanac).first

  def open?(almanac, day, period) = almanac.on?(times, day, period)

  # The part of the day it ends in, begun now: "Evening".
  def ends(almanac, period) = almanac.later(period, takes).first

  # How the table sees it, begun now: "Attend class (until Evening)", or,
  # past the day's end, "The Undertow (until Morning, tomorrow)".
  def label(almanac, period)
    ends, days = almanac.later(period, takes)
    "#{name} (until #{ends}#{', tomorrow' if days.positive?})"
  end
end
