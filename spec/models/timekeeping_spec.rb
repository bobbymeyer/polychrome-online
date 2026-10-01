# frozen_string_literal: true

require "rails_helper"

RSpec.describe Campaign::Timekeeping do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Rust") }

  it "passes the parts of the day, and each new day ticks the dawn clocks" do
    festival = campaign.clocks.create!(name: "The festival", segments: 3, triggers: %w[dawn], public: true, full_line: "Lanterns everywhere: the festival begins.")
    expect(campaign.when_it_is).to eq("Day 1 · dawn")
    expect(campaign.parts_gone).to eq(0)
    campaign.pass_time!(2)
    expect([ campaign.day, campaign.time_of_day ]).to eq([ 1, "dusk" ])
    expect(campaign.parts_gone).to eq(2) # the day clock's turn: only ever forward
    expect(campaign.messages.last.body).to eq("Dusk.")

    expect(campaign.pass_time!(campaign.until_the_day_begins)).to eq(1)
    expect([ campaign.day, campaign.time_of_day ]).to eq([ 2, "dawn" ])
    expect(campaign.parts_gone).to eq(4) # round into the next day, not back to 0
    expect(campaign.almanac.periods.map { |part| campaign.daylight(part) }).to eq(%w[dawn day dusk night])
    expect(festival.reload.filled).to eq(1)

    campaign.pass_time!(8)
    expect(campaign.day).to eq(4)
    expect(festival.reload).to be_full
    expect(campaign.messages.pluck(:body)).to include("Lanterns everywhere: the festival begins.", "2 days pass. Day 4: dawn.")
  end

  it "sleeps until dawn on a rest, and takes a road's time on a journey" do
    a = campaign.map_nodes.create!(name: "A", kind: "town", x: 1, y: 1, visible: true)
    b = campaign.map_nodes.create!(name: "B", kind: "town", x: 9, y: 9, visible: true)
    road = campaign.map_edges.create!(from_node: a, to_node: b, duration: 3)
    campaign.place_party!(a)
    campaign.reload.travel!(road)
    expect(campaign.reload.time_of_day).to eq("night")
    expect(campaign.messages.where(body: "Night.")).not_to exist # a journey only says so when a day starts

    campaign.sleep!
    expect([ campaign.day, campaign.time_of_day ]).to eq([ 2, "dawn" ])

    # Begun at dawn, a rest takes the morning: it never skips a whole day.
    expect(campaign.until_the_day_begins).to eq(0)
    campaign.sleep!
    expect([ campaign.day, campaign.time_of_day ]).to eq([ 2, "day" ])

    # A step through a door takes no time at all.
    c = campaign.map_nodes.create!(name: "Platform Zero", kind: "landmark", x: 20, y: 20, visible: true)
    platform = campaign.map_edges.create!(from_node: b, to_node: c, duration: 0)
    campaign.reload.travel!(platform)
    expect([ campaign.reload.day, campaign.time_of_day ]).to eq([ 2, "day" ])
  end

  it "keeps the world's own parts of the day, and sleeps until its first" do
    world.update!(calendar: { periods: "Morning, After school, Evening, Late night", dark: "Late night" })
    school = world.campaigns.create!(name: "Third Term")
    expect(school.when_it_is).to eq("Day 1 · Morning")
    school.pass_time!(3)
    expect([ school.period, school.dark? ]).to eq([ "Late night", true ])
    expect(school.rest_time).to eq(1)
    school.pass_time!(school.rest_time)
    expect([ school.day, school.period ]).to eq([ 2, "Morning" ])
    expect(school.messages.last.body).to eq("Day 2: Morning.")
    expect { school.update!(time_of_day: "dawn") }.to raise_error(ActiveRecord::RecordInvalid, /isn't a part of the day/)
  end

  it "ticks a clock kept to the calendar only then, for each day that begins in a long wait" do
    world.update!(calendar: { weekdays: "Moonsday, Tidesday, Ashday", months: "Thaw (30, Spring)" })
    market = campaign.clocks.create!(name: "Market day", segments: 5, triggers: %w[dawn], times: %w[Ashday])
    daily = campaign.clocks.create!(name: "The tide", segments: 9, triggers: %w[dawn])
    expect(market.ticking).to eq("each new day, on Ashday")
    expect { campaign.clocks.create!(name: "Bad", segments: 2, times: %w[Funday]) }.to raise_error(ActiveRecord::RecordInvalid, /Funday isn't in the calendar/)

    campaign.pass_time!(4 * 5) # five days begin: Tidesday, Ashday, Moonsday, Tidesday, Ashday
    expect(market.reload.filled).to eq(2)
    expect(daily.reload.filled).to eq(5)
  end

  it "names the days the world's way" do
    world.update!(calendar: { weekdays: "Moonsday, Tidesday", months: "Thaw, Rainfall", month_length: 30 })
    campaign.update!(day: 32)
    expect(campaign.when_it_is).to eq("Tidesday, 2 Rainfall · dawn")
  end
end
