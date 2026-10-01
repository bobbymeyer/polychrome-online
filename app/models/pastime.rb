# frozen_string_literal: true

# Something to do at a place: go to class, work a shift, see someone, take
# rooms at the inn, go down into the other world at night. It can take part
# of a day, cost money, and make something happen (Outcome). A place lists
# them one per line, the way scenes are written:
#
#   Attend class (morning, after school, 2): The bell. Maths, then lunch.
#   Work a shift (day, 2, money 40): Aprons, and the till that sticks.
#   Swim at the lido (summer, weekend): Chlorine and shrieking.
#   Stay at the Gull (pay 25, rest): The beds are soft.
#   The Undertow (late night, 2)
#
# In brackets, in any order:
#   - when it can be done, in the setting's calendar words (parts of the
#     day, days of the week, months, seasons: Pointcrawl::Calendar#on?);
#     any time, if none are given;
#   - how many parts of the day it takes (one, if not given; 0 for a moment);
#   - what it costs the party: "pay 25";
#   - what it does: the outcomes, "money 40", "exp 20", "rumour", "rest",
#     "restore 25", "raise", "find 100" and the rest (Outcome::KINDS).
# After the colon, what the table hears when the party does it. The table
# picks one like a way on (Campaign::Ways): a vote, settled by the GM.
#
# A town's inn, temple and guild are things to do as well, made from the
# town (Location::Town#services_for), and so is making camp on the road.
#
# A townsperson's wish the party can meet is one too (Location::Wishes):
# its wish is the townsperson's key, and doing it hands over what they want.
Pastime = Data.define(:name, :times, :takes, :line, :price, :outcomes, :service, :wish)

class Pastime
  # A colon only ends the name when a space follows it: "Wait for the 0:13 (night)".
  FORMAT = /\A(?<name>(?:[^():]|:(?!\s))+?)\s*(?:\((?<when>[^)]*)\))?\s*(?::\s+(?<line>.*)|:)?\z/

  def initialize(name:, times: [], takes: 1, line: nil, price: 0, outcomes: [], service: nil, wish: nil)
    super
  end

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
      outcomes = []
      takes = 1
      price = 0
      most = almanac.periods.size
      match[:when].to_s.split(%r{\s*[/,]\s*}).map(&:strip).reject(&:empty?).each do |word|
        if word.match?(/\A\d+\z/) then takes = word.to_i
        elsif (paid = word[/\Apay\s+(\d+)\z/i, 1]) then price = paid.to_i
        elsif (kind = almanac.kind_of(word)) then times << almanac.words[kind].find { |name| name.casecmp?(word) }
        elsif (outcome = Outcome.parse(word)) then outcomes << outcome
        elsif word.downcase != "any"
          problems << "“#{match[:name]}”: #{word} isn't in the calendar (a part of the day, a day of the week, a month or a season), " \
                      "a price (pay 20), an outcome (#{Outcome::KINDS.keys.first(5).map { |k| k.tr('_', ' ') }.join(', ')}…) or a number of parts"
        end
      end
      problems << "“#{match[:name]}” takes 0 to #{most} parts of the day" unless takes.between?(0, most)
      new(name: match[:name].strip, times: times, takes: takes.clamp(0, most), line: match[:line].to_s.strip.presence,
          price: price, outcomes: outcomes)
    end
    dupes = pastimes.map(&:name).tally.select { |_, n| n > 1 }.keys
    problems << "#{dupes.to_sentence} is listed twice" if dupes.any?
    [ pastimes, problems ]
  end

  def self.list(text, almanac = Pointcrawl::Calendar.new) = parse(text, almanac).first

  def open?(almanac, day, period) = almanac.on?(times, day, period)

  # A night's sleep: it takes until the day begins, whatever else is said.
  def rest? = outcomes.any? { |outcome| outcome.kind == "rest" }

  # The part of the day it ends in, begun now: "Evening".
  def ends(almanac, period) = almanac.later(period, takes).first

  # How the table sees it, begun now: "Attend class (until Evening)",
  # "The Undertow (until Morning, tomorrow)", "Rooms at the Gull (50 gil,
  # overnight)". cost: its price, in the world's money, if it has one.
  def label(almanac, period, cost: nil)
    ends, days = almanac.later(period, takes)
    time = if rest? then "overnight"
    elsif takes.positive? then "until #{ends}#{', tomorrow' if days.positive?}"
    end
    details = [ cost, time ].compact
    details.empty? ? name : "#{name} (#{details.join(', ')})"
  end
end
