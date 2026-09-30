# frozen_string_literal: true

require "rails_helper"

RSpec.describe Recap do
  include ActiveSupport::Testing::TimeHelpers

  let(:campaign) { create_campaign }
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let!(:cid) { campaign.npcs.create!(name: "Cid") }

  def at(time, &)
    travel_to(time, &)
  end

  let(:last_week) { 7.days.ago.change(hour: 19) }
  let(:tonight) { 1.hour.ago }

  before do
    at(last_week - 7.days) { campaign.messages.create!(kind: "system", body: "The party is at Tule.") }
    at(last_week) do
      campaign.messages.create!(kind: "system", body: "The party travels from Tule to Carwen.")
      campaign.messages.create!(kind: "system", body: "Wind Shrine: the party enters Hall.")
      campaign.messages.create!(kind: "system", cue: "key", body: "Found the Crystal Key in Hall.")
      campaign.messages.create!(scope: "whisper", speaker: bartz, body: "psst, secret")
      campaign.flags.create!(key: "met_cid", public: true)
      campaign.flags.create!(key: "gm_secret", value: "twist")
      battle = start_battle(campaign: campaign)
      battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
    end
    at(last_week + 2.hours) { campaign.messages.create!(speaker: cid, expression: "worried", body: "The crystal is cracking.") }
  end

  it "recaps the last session that ended: the road, battles, finds, what the party learned, and the last word" do
    recap = described_class.for(campaign)
    expect(recap.places).to eq([ "Carwen", "Wind Shrine" ])
    expect(recap.battle_lines).to eq([ "Won: Test battle" ])
    expect(recap.found).to eq([ "Found the Crystal Key in Hall." ])
    expect(recap.learned).to eq([ "Met cid" ])
    expect(recap.last_line).to have_attributes(body: "The crystal is cracking.", speaker: cid)
    expect(recap.ended_at).to be_within(1.second).of(last_week + 2.hours)
    expect(recap.lines.map(&:body)).not_to include("psst, secret")
  end

  it "dates the session in story time, as every line is" do
    expect(campaign.messages.last).to have_attributes(day: 1, time_of_day: "dawn", story_time: "Dawn")
    expect(described_class.for(campaign).ended_on).to eq("Day 1")
    campaign.world.update!(calendar: { weekdays: "Moonsday, Tidesday", months: "Thaw", month_length: 30 })
    expect(described_class.for(campaign.reload).ended_on).to eq("Moonsday, 1 Thaw")
  end

  it "keeps recapping last week once tonight's session has started" do
    at(tonight) { campaign.messages.create!(body: "Welcome back.") }
    expect(described_class.for(campaign).last_line.body).to eq("The crystal is cracking.")
  end

  it "has nothing to say for a table with no log" do
    expect(described_class.for(create_campaign(world: campaign.world, name: "Fresh"))).to be_nil
  end
end
