# frozen_string_literal: true

require "rails_helper"

RSpec.describe Timekeeping do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Rust") }

  it "passes the parts of the day, and each new day ticks the dawn clocks" do
    festival = campaign.clocks.create!(name: "The festival", segments: 3, triggers: %w[dawn], public: true, full_line: "Lanterns everywhere: the festival begins.")
    expect(campaign.when_it_is).to eq("Day 1 · dawn")
    campaign.pass_time!(2)
    expect([ campaign.day, campaign.time_of_day ]).to eq([ 1, "dusk" ])
    expect(campaign.messages.last.body).to eq("Dusk.")

    expect(campaign.pass_time!(campaign.until_dawn)).to eq(1)
    expect([ campaign.day, campaign.time_of_day ]).to eq([ 2, "dawn" ])
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

    campaign.rest!
    expect([ campaign.day, campaign.time_of_day ]).to eq([ 2, "dawn" ])
  end

  it "names the days the world's way" do
    world.update!(calendar: { weekdays: "Moonsday, Tidesday", months: "Thaw, Rainfall", month_length: 30 })
    campaign.update!(day: 32)
    expect(campaign.when_it_is).to eq("Tidesday, 2 Rainfall · dawn")
  end
end
