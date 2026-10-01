# frozen_string_literal: true

# A story table's coverage (Story::Coverage) over a world's moments: a few
# hundred of them, seeded, spread across its kinds of place, its parts of
# the day and calendar, the party's state, the moment the table is for
# (arriving, a failed check, camp or the road) and every flag or key its
# rows ask about, set and not. What a world builder reads to see where a
# table is thin (docs/STORY.md, Later: the coverage page).
class StoryCoverage
  MOMENTS = 300
  PLACES = %w[town dungeon landmark wilds field].freeze
  # Facts the game makes itself (Campaign::Moment, Campaign::Remarks); any
  # other key a row asks about is a flag or a secret's key, set or not.
  MADE = %w[place town dungeon landmark wilds field mode first_visit visits cleared standing reputation time dawn day dusk night dark days
            weekday month season party hurt down home gil hurt_one tied tied_to check who failed succeeded stat skill move difficulty
            easy normal hard heroic rest camp inn road journey to].freeze

  attr_reader :table, :world

  def initialize(table)
    @table = table
    @world = table.world
  end

  def rows = table.entries

  def avoid = [ world.lines, world.veils ].flat_map { |text| text.to_s.lines.map(&:strip) }.compact_blank

  def report
    @report ||= Story::Coverage.run(rows, moments, avoid: avoid)
  end

  # { "town · night" => [moments, nothing fits] }
  def slots = Story::Coverage.slots(moments, report["empty"]) { |facts| slot(facts) }

  def slot(facts)
    where = PLACES.find { |kind| facts[kind] } || "on the road"
    [ (if facts["camp"] then "camp" elsif facts["inn"] then "inn" end), where, light(facts) ].compact.join(" · ")
  end

  # Every row that fits a moment the writer makes up: a kind of place, a
  # part of the day, and facts written as a row remembers them ("hurt = 2,
  # smoke_seen").
  def try(place:, period:, extra:)
    writes, problems = Story::Criteria.parse_writes(extra)
    facts = base(place, period).merge(writes.to_h { |w| [ w.key, w.op == "=" ? w.value : w.value.to_i ] })
    facts = facts.transform_values { |v| v.is_a?(String) && v.match?(/\A-?\d+\z/) ? v.to_i : v }
    [ Story::Coverage.rank(rows, facts, avoid: avoid), facts, problems ]
  end

  def periods = world.almanac.periods

  def moments
    @moments ||= begin
      dice = Battle::Rng.new(Battle::Rng.seed_state(table.id.to_i * 2_654_435_761))
      asked = Story::Coverage.asked(rows).except(*MADE)
      Array.new(MOMENTS) { moment(dice, asked) }
    end
  end

  private

  def base(place, period)
    facts = { "place" => "Somewhere", place => true, "time" => period.downcase, Campaign::Moment.key(period) => true, "dark" => world.almanac.dark?(period),
              "visits" => 0, "first_visit" => true, "party" => 3, "hurt" => 0, "down" => 0, "gil" => 100, "days" => 1 }
    facts[daylight(period)] = true
    facts.merge(kind_facts_for_try)
  end

  def kind_facts_for_try
    case table.kind
    when "complications" then { "check" => true, "who" => "Rook", "failed" => 1, "succeeded" => 0 }
    when "events" then { "road" => true, "journey" => true, "to" => "Somewhere" }
    else {}
    end
  end

  def moment(dice, asked)
    pick = ->(list) { list[dice.int(list.size)] }
    on_road = table.kind == "events" && dice.percent?(50)
    kind = on_road ? "road" : pick.(PLACES)
    period = pick.(periods)
    party = 1 + dice.int(4)
    hurt = dice.int(party + 1)
    visits = dice.int(4)
    facts = { "time" => period.downcase, Campaign::Moment.key(period) => true, "dark" => world.almanac.dark?(period), daylight(period) => true,
              "days" => 1 + dice.int(30), "party" => party, "hurt" => hurt, "down" => dice.int(2), "gil" => dice.int(300) }
    facts["hurt_one"] = "Rook" if hurt.positive?
    facts["home"] = "Vivi" if dice.percent?(25)
    facts.merge!("tied" => "Vivi", "tied_to" => "Mara") if dice.percent?(30)
    world.almanac.words.slice("weekdays", "months", "seasons").each do |what, names|
      next if names.empty?

      name = pick.(names)
      facts[{ "weekdays" => "weekday", "months" => "month", "seasons" => "season" }[what]] = name.downcase
      facts[Campaign::Moment.key(name)] = true
    end
    Array(world.origins).each { |origin| facts["from_#{Campaign::Moment.key(origin['slug'])}"] = "Vivi" if dice.percent?(20) }
    facts.merge!(place_facts(kind, visits, dice, pick), kind_facts(dice, pick, party, on_road))
    asked.each do |key, how|
      next if dice.percent?(50) # not set

      facts[key] = if how["numbers"] then dice.int(4)
      elsif how["values"].any? && dice.percent?(70) then pick.(how["values"])
      else "yes"
      end
    end
    facts
  end

  def place_facts(kind, visits, dice, pick)
    return {} if kind == "road"

    facts = { "place" => "Somewhere", kind => true, "visits" => visits, "first_visit" => visits.zero? }
    facts["cleared"] = dice.percent?(25) if kind == "dungeon"
    if kind == "town"
      reputation = dice.int(11) - 5
      facts.merge!("reputation" => reputation, "standing" => Location::Town::STANDINGS.find { |range, _| range.cover?(reputation) }.last.downcase)
    end
    facts
  end

  def kind_facts(dice, pick, party, on_road)
    case table.kind
    when "complications"
      failed = 1 + dice.int(party)
      difficulty = pick.(Stats::Check::DIFFICULTIES.keys)
      facts = { "check" => true, "who" => "Rook", "failed" => failed, "succeeded" => party - failed, "stat" => pick.(Stats::Check::STATS),
                "difficulty" => difficulty, difficulty => true }
      if (skills = Array(world.skills)).any? && dice.percent?(60)
        skill = Campaign::Moment.key(pick.(skills)["name"])
        facts.merge!("skill" => skill, skill => true)
      end
      facts
    when "events"
      on_road ? { "road" => true, "journey" => true, "to" => "Somewhere" } : { "rest" => true, (dice.percent?(50) ? "camp" : "inn") => true }
    else {}
    end
  end

  # The light, as Campaign::Timekeeping#daylight has it.
  def daylight(period)
    almanac = world.almanac
    index = almanac.period_index(period)
    return "night" if almanac.dark?(period)
    return "dawn" if index.zero?

    almanac.dark?(almanac.periods[(index + 1) % almanac.periods.size]) ? "dusk" : "day"
  end

  def light(facts) = %w[dawn day dusk night].find { |word| facts[word] == true }
end
