# frozen_string_literal: true

module Pointcrawl
  # A world's calendar, read. Each world sets its own, and each part is
  # made of the one before: parts of the day make a day, days a week (its
  # weekdays) and a month, months a season and a year, and years an era.
  # A world with none of it has four parts to a day and counts days.
  #
  #   { "periods" => ["Morning", "After school", "Evening", "Late night"],
  #     "dark" => ["Late night"],
  #     "weekdays" => ["Monday", ...],
  #     "months" => [{ "name" => "April", "days" => 30, "season" => "Spring" }, ...],
  #     "start" => { "year" => 2009, "month" => 0, "day" => 7, "weekday" => 1 },
  #     "eras" => [{ "label" => "Heisei #", "from" => 1989 }] }
  #
  # The day begins with the first part: a night's sleep ends there. The
  # dark parts are its night (a place's "by night"). Campaign days count
  # from 1, which falls on the start date.
  #
  # Pure.
  class Calendar
    PERIODS = %w[dawn day dusk night].freeze
    # The kinds of word a thing's "when" can use, and how they're said.
    KINDS = { "periods" => "a part of the day", "weekdays" => "a day of the week", "months" => "a month", "seasons" => "a season" }.freeze
    MAX_NAMES = 24

    # Where a day falls: its weekday, date ("7 April"), month, season and
    # year (with its era: "Heisei 21"), each nil if the world doesn't have it.
    Moment = Data.define(:day, :weekday, :date, :month, :season, :year)

    attr_reader :periods, :dark, :weekdays, :months, :eras, :start

    def initialize(settings = nil)
      settings = stringify(settings || {})
      @periods = names(settings["periods"])
      @periods = PERIODS if @periods.empty?
      dark = names(settings["dark"]).map(&:downcase)
      @dark = @periods.select { |period| dark.include?(period.downcase) }
      @dark = [ @periods.last ] if @dark.empty? && @periods.size > 1
      @weekdays = names(settings["weekdays"])
      length = settings["month_length"].to_i
      @months = Array(settings["months"]).first(MAX_NAMES).filter_map do |month|
        month = month.is_a?(Hash) ? stringify(month) : { "name" => month }
        name = month["name"].to_s.strip
        next if name.empty?

        season = month["season"].to_s.strip
        { "name" => name, "days" => (month["days"] || length).to_i.clamp(0, 400), "season" => (season unless season.empty?) }
      end
      start = stringify(settings["start"] || {})
      @start = { "year" => (start["year"].to_i if start["year"].to_s.match?(/\A-?\d+\z/)),
                 "month" => start["month"].to_i.clamp(0, [ @months.size - 1, 0 ].max),
                 "day" => [ start["day"].to_i, 1 ].max, "weekday" => start["weekday"].to_i }
      @eras = Array(settings["eras"]).filter_map do |era|
        era = stringify(era)
        label = era["label"].to_s.strip
        { "label" => label, "from" => era["from"].to_i } unless label.empty?
      end.sort_by { |era| era["from"] }
    end

    # As stored: what #initialize reads.
    def to_h
      { "periods" => periods, "dark" => dark, "weekdays" => weekdays, "months" => months, "start" => start, "eras" => eras }
    end

    def seasons = months.filter_map { |month| month["season"] }.uniq

    # Days in a year: none if its months don't say how long they are.
    def year_length
      months.all? { |month| month["days"].positive? } ? months.sum { |month| month["days"] } : 0
    end

    # The part of the day by name (any case), or nil.
    def period(name) = periods.find { |period| period.casecmp?(name.to_s) }

    # Where a part of the day falls in it; the first, for one it doesn't have.
    def period_index(name) = periods.index(period(name)) || 0

    def dark?(name) = dark.include?(period(name))

    # The part of the day `parts` after this one, and how many days that crosses.
    def later(name, parts)
      index = period_index(name) + parts
      [ periods[index % periods.size], index / periods.size ]
    end

    def moment(day)
      index = day.to_i - 1
      weekday = weekdays.empty? ? nil : weekdays[(start["weekday"] + index) % weekdays.size]
      length = year_length
      return Moment.new(day: day, weekday: weekday, date: nil, month: nil, season: nil, year: nil) unless length.positive?

      offset = months.first(start["month"]).sum { |month| month["days"] } + start["day"] - 1 + index
      years, into = offset.divmod(length)
      month = months.find do |m|
        next true if into < m["days"]

        into -= m["days"]
        false
      end
      Moment.new(day: day, weekday: weekday, date: "#{into + 1} #{month['name']}", month: month["name"], season: month["season"],
                 year: start["year"] && year_label(start["year"] + years))
    end

    # "Moonsday, 12 Rainfall", or "Day 12" for a world that doesn't have months.
    def date(day)
      at = moment(day)
      upcase_first([ at.weekday, at.date || "day #{day}" ].compact.join(", "))
    end

    # "Spring · Heisei 21": what the date doesn't say.
    def season_and_year(day)
      at = moment(day)
      [ at.season, at.year ].compact.join(" · ")
    end

    # "Heisei 21" (era "Heisei #", from 1989), "1203 AC" (era "AC",
    # from 1), or the year alone before any era.
    def year_label(year)
      era = eras.reverse.find { |e| e["from"] <= year }
      return year.to_s unless era

      within = year - era["from"] + 1
      era["label"].include?("#") ? era["label"].gsub("#", within.to_s) : "#{within} #{era['label']}"
    end

    # The names a "when" can use, by kind.
    def words
      { "periods" => periods, "weekdays" => weekdays, "months" => months.map { |month| month["name"] }, "seasons" => seasons }
    end

    # Which kind of word it is ("periods"), or nil if the calendar doesn't have it.
    def kind_of(word)
      words.find { |_, names| names.any? { |name| name.casecmp?(word.to_s.strip) } }&.first
    end

    # The words it doesn't have.
    def unknown(when_words) = Array(when_words).reject { |word| kind_of(word) }

    # Whether it's one of those times now. Words of one kind are any of
    # them ("dawn, dusk"); of different kinds, all at once ("winter,
    # night": winter nights). No words at all is any time. A word the
    # calendar has lost is passed over.
    def on?(when_words, day, period_name)
      at = moment(day)
      now = { "periods" => period(period_name), "weekdays" => at.weekday, "months" => at.month, "seasons" => at.season }
      Array(when_words).group_by { |word| kind_of(word) }.all? do |kind, said|
        kind.nil? || said.any? { |word| word.to_s.strip.casecmp?(now[kind].to_s) }
      end
    end

    # The form's text, as a calendar's settings, and what's wrong with it.
    #   months: one a line, "April (30, Spring)"; or names with commas and a
    #   month_length. eras: one a line, "Heisei # (1989)".
    def self.read(form)
      form = form.to_h.transform_keys(&:to_s)
      # Settings as stored (a world copied, the seeds): their start as the form's.
      if form["start"].is_a?(Hash)
        start = form["start"].transform_keys(&:to_s)
        months = Array(form["months"])
        weekdays = Array(form["weekdays"])
        form = form.merge("start_year" => start["year"], "start_day" => start["day"],
                          "start_month" => months[start["month"].to_i].then { |m| m.is_a?(Hash) ? m["name"] || m[:name] : m },
                          "start_weekday" => weekdays[start["weekday"].to_i])
      end
      problems = []
      split = ->(text) { text.is_a?(Array) ? text.map(&:to_s) : text.to_s.split(/[,\n]/) }
      clean = ->(list) { split.(list).map(&:strip).reject(&:empty?) }
      periods = clean.(form["periods"])
      problems << "a day needs at least two parts" if periods.size == 1
      dupes = periods.map(&:downcase).tally.select { |_, n| n > 1 }.keys
      problems << "#{dupes.join(', ')} is a part of the day twice" if dupes.any?
      periods = periods.uniq(&:downcase).first(MAX_NAMES)
      dark = clean.(form["dark"])
      stray = dark.reject { |name| (periods.empty? ? PERIODS : periods).any? { |p| p.casecmp?(name) } }
      problems << "#{stray.join(', ')} isn't a part of the day" if stray.any?

      months = months_from(form["months"], form["month_length"].to_i, problems)
      eras = (form["eras"].is_a?(Array) ? form["eras"] : form["eras"].to_s.lines).filter_map do |line|
        next line.transform_keys(&:to_s) if line.is_a?(Hash)

        line = line.to_s.strip
        next if line.empty?

        match = line.match(/\A(?<label>[^()]+?)\s*\((?<from>-?\d+)\)\z/)
        next match && { "label" => match[:label], "from" => match[:from].to_i } if match

        problems << "“#{line}” needs the year it began, in brackets: “Heisei # (1989)”"
        nil
      end

      weekdays = clean.(form["weekdays"]).first(MAX_NAMES)
      start_month = months.index { |month| month["name"].casecmp?(form["start_month"].to_s.strip) }
      problems << "#{form['start_month']} isn't one of the months" if form["start_month"].to_s.strip != "" && !start_month
      start_weekday = weekdays.index { |name| name.casecmp?(form["start_weekday"].to_s.strip) }
      problems << "#{form['start_weekday']} isn't one of the days of the week" if form["start_weekday"].to_s.strip != "" && !start_weekday
      if start_month && form["start_day"].to_i > months[start_month]["days"] && months[start_month]["days"].positive?
        problems << "#{months[start_month]['name']} has only #{months[start_month]['days']} days"
      end

      settings = {
        "periods" => periods, "dark" => dark, "weekdays" => weekdays, "months" => months, "eras" => eras,
        "start" => { "year" => (form["start_year"].to_i if form["start_year"].to_s.strip.match?(/\A-?\d+\z/)),
                     "month" => start_month || 0, "day" => [ form["start_day"].to_i, 1 ].max, "weekday" => start_weekday || 0 }
      }
      [ settings, problems ]
    end

    def self.months_from(text, length, problems)
      lines = text.is_a?(Array) ? text : text.to_s.split(text.to_s.include?("\n") ? "\n" : /,(?![^(]*\))/)
      lines.map { |line| line.is_a?(Hash) ? line : line.to_s.strip }.reject { |line| line == "" }.first(MAX_NAMES).filter_map do |line|
        next line.transform_keys(&:to_s) if line.is_a?(Hash)

        match = line.match(/\A(?<name>[^()]+?)\s*(?:\((?<details>[^)]*)\))?\z/)
        unless match
          problems << "“#{line}”: a month is written “April (30, Spring)”"
          next
        end
        days = length
        season = nil
        match[:details].to_s.split(",").map(&:strip).reject(&:empty?).each do |detail|
          if detail.match?(/\A\d+\z/) then days = detail.to_i
          else season = detail
          end
        end
        problems << "#{match[:name]} needs a number of days" unless days.positive?
        { "name" => match[:name], "days" => days, "season" => season }
      end
    end

    # The months as the form writes them.
    def months_text
      months.map do |month|
        details = [ (month["days"] if month["days"].positive?), month["season"] ].compact
        details.empty? ? month["name"] : "#{month['name']} (#{details.join(', ')})"
      end.join("\n")
    end

    def eras_text = eras.map { |era| "#{era['label']} (#{era['from']})" }.join("\n")

    private

    def names(list)
      list = list.split(",") if list.is_a?(String)
      Array(list).map { |name| name.to_s.strip }.reject(&:empty?).first(MAX_NAMES)
    end

    def stringify(hash) = hash.to_h.transform_keys(&:to_s)

    def upcase_first(text) = text.empty? ? text : text[0].upcase + text[1..]
  end
end
