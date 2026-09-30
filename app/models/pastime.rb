# frozen_string_literal: true

# Something to do at a place that takes part of a day: go to class, work a
# shift, see someone, go down into the other world at night. A place lists
# them one per line, the way scenes are written:
#
#   Attend class (dawn/day, 2): The bell. Maths, then lunch on the roof.
#   Visit the shrine: Incense, and the sound of the sea.
#   The Undertow (night, 4)
#
# In brackets: the parts of the day it can be done in (any, if none are
# given) and how many parts it takes (one, if not given). After the colon,
# what the table hears when the party does it. The table picks one like a
# way on (Campaign::Ways): a vote, settled by the GM, and time passes.
Pastime = Data.define(:name, :times, :takes, :line)

class Pastime
  TIMES = Campaign::Timekeeping::TIMES
  FORMAT = /\A(?<name>[^():]+?)\s*(?:\((?<when>[^)]*)\))?\s*(?::\s*(?<line>.*))?\z/

  # [pastimes, problems] from a place's text.
  def self.parse(text)
    problems = []
    pastimes = text.to_s.lines.map(&:strip).reject(&:empty?).filter_map do |raw|
      match = FORMAT.match(raw)
      unless match
        problems << "“#{raw.truncate(40)}” needs a name before any brackets or colon"
        next
      end

      times = []
      takes = 1
      match[:when].to_s.split(%r{[/,\s]+}).reject(&:empty?).each do |word|
        if word.match?(/\A\d+\z/) then takes = word.to_i
        elsif TIMES.include?(word.downcase) then times << word.downcase
        elsif word.downcase != "any" then problems << "“#{match[:name]}”: #{word} isn't a part of the day (#{TIMES.join(', ')}) or a number of parts"
        end
      end
      problems << "“#{match[:name]}” takes 1 to 4 parts of the day" unless takes.between?(1, 4)
      new(name: match[:name].strip, times: times.presence || TIMES, takes: takes.clamp(1, 4), line: match[:line].to_s.strip.presence)
    end
    dupes = pastimes.map(&:name).tally.select { |_, n| n > 1 }.keys
    problems << "#{dupes.to_sentence} is listed twice" if dupes.any?
    [ pastimes, problems ]
  end

  def self.list(text) = parse(text).first

  def open_at?(time_of_day) = times.include?(time_of_day)

  # The part of the day it ends in, begun now: "dusk".
  def ends(time_of_day)
    TIMES[(TIMES.index(time_of_day) + takes) % TIMES.size]
  end

  # How the table sees it, begun now: "Attend class (until dusk)", or,
  # past the next dawn, "The Undertow (until night, tomorrow)".
  def label(time_of_day)
    tomorrow = TIMES.index(time_of_day) + takes > TIMES.size
    "#{name} (until #{ends(time_of_day)}#{', tomorrow' if tomorrow})"
  end
end
