# frozen_string_literal: true

RSpec.describe Pointcrawl::Calendar do
  # A school year: four parts to a day, the week from Monday, months with
  # their own lengths and seasons, starting on Tuesday 7 April 2009.
  let(:school) do
    settings, problems = described_class.read(
      "periods" => "Morning, After school, Evening, Late night", "dark" => "Late night",
      "weekdays" => "Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday",
      "months" => "April (30, Spring)\nMay (31, Spring)\nJune (30, Summer)", "eras" => "Heisei # (1989)",
      "start_year" => "2009", "start_month" => "april", "start_day" => "7", "start_weekday" => "Tuesday"
    )
    expect(problems).to be_empty
    described_class.new(settings)
  end

  it "counts days, in four parts, when the world sets nothing" do
    calendar = described_class.new
    expect(calendar.periods).to eq(%w[dawn day dusk night])
    expect(calendar.dark).to eq(%w[night])
    expect(calendar.date(12)).to eq("Day 12")
    expect(calendar.season_and_year(12)).to eq("")
    expect(calendar.later("dusk", 3)).to eq([ "day", 1 ])
  end

  it "composes parts into days, days into weeks and months, months into seasons and years, and years into eras" do
    expect(school.date(1)).to eq("Tuesday, 7 April")
    expect(school.season_and_year(1)).to eq("Spring · Heisei 21")
    expect(school.date(25)).to eq("Friday, 1 May")
    at = school.moment(56)
    expect([ at.weekday, at.date, at.season ]).to eq([ "Monday", "1 June", "Summer" ])
    # 91 days make the year: 7 April comes round again, a year on.
    expect(school.date(92)).to eq("Tuesday, 7 April")
    expect(school.season_and_year(92)).to eq("Spring · Heisei 22")
    expect(school.later("Evening", 2)).to eq([ "Morning", 1 ])
    expect(school.dark?("late night")).to be(true)
  end

  it "says the year the era's way" do
    calendar = described_class.new("months" => [ { "name" => "Thaw", "days" => 10 } ], "start" => { "year" => 1203 },
                                    "eras" => [ { "label" => "AC", "from" => 1 }, { "label" => "Year # of the Tide", "from" => 1204 } ])
    expect(calendar.moment(1).year).to eq("1203 AC")
    expect(calendar.moment(11).year).to eq("Year 1 of the Tide")
  end

  it "keeps the old settings: month names and one length" do
    calendar = described_class.new("weekdays" => %w[Moonsday Tidesday], "months" => %w[Thaw Rainfall], "month_length" => 30)
    expect(calendar.date(32)).to eq("Tidesday, 2 Rainfall")
    expect(described_class.new("months" => %w[Thaw]).date(3)).to eq("Day 3") # no length: days are counted
  end

  it "knows whether it's a time: any word of a kind, all of the kinds" do
    expect(school.kind_of("SPRING")).to eq("seasons")
    expect(school.unknown(%w[spring winter])).to eq(%w[winter])
    expect(school.on?(%w[Spring], 1, "Morning")).to be(true)
    expect(school.on?([ "Summer", "Late night" ], 1, "Late night")).to be(false)
    expect(school.on?([ "Spring", "Late night", "Evening" ], 1, "Evening")).to be(true)
    expect(school.on?(%w[Monday Wednesday], 1, "Morning")).to be(false) # a Tuesday
    expect(school.on?([], 1, "Morning")).to be(true)
  end

  it "says what's wrong with the form" do
    _, problems = described_class.read("periods" => "Day", "dark" => "Night", "months" => "April (Spring)", "eras" => "Heisei",
                                       "start_month" => "Maytember")
    expect(problems).to include("a day needs at least two parts", "Night isn't a part of the day", "April needs a number of days",
                                "“Heisei” needs the year it began, in brackets: “Heisei # (1989)”", "Maytember isn't one of the months")
  end

  it "reads its own settings back" do
    expect(described_class.new(described_class.read(school.to_h).first).to_h).to eq(school.to_h)
    settings, = described_class.read("months" => school.months_text, "eras" => school.eras_text)
    expect(settings["months"]).to eq(school.months)
    expect(settings["eras"]).to eq(school.eras)
  end
end
