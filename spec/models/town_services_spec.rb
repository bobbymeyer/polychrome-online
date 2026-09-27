# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Town services" do
  let(:campaign) { create_campaign.tap { |c| c.update!(gil: 1000) } }
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let!(:lenna) { create_character(campaign, name: "Lenna") }
  let(:town) do
    Struct.new(:name, :view).new("Tule", "services" => [
      { "kind" => "inn", "name" => "The Tipsy Wyvern" }, { "kind" => "temple", "name" => "Chapel of Light" },
      { "kind" => "guild", "name" => "Adventurers' Guild" }
    ])
  end

  it "charges by level, with a floor" do
    expect(campaign.service_price("inn", bartz)).to eq(25) # level 5
    expect(campaign.service_price("temple", bartz)).to eq(100)
    expect(campaign.service_price("guild", bartz)).to eq(30)
  end

  it "rests the standing at the inn, raises the fallen at the temple, and sells rumours at the guild" do
    bartz.update!(hp: 0)
    lenna.update!(hp: 5, mp: 1)
    expect { campaign.use_service!("inn", bartz, at: town, by: "Bartz") }.to raise_error(ArgumentError, /A temple can/)
    expect { campaign.use_service!("temple", lenna, at: town, by: "Lenna") }.to raise_error(ArgumentError, /on their feet/)

    campaign.use_service!("temple", bartz, at: town, by: "Lenna")
    expect(bartz.reload).to be_conscious
    expect(campaign.messages.last.body).to eq("Lenna, for Bartz, pays 100 gil at Chapel of Light. Bartz is raised, whole again.")

    campaign.use_service!("guild", lenna, at: town, by: "Lenna")
    expect(campaign.messages.last.body).to include("buys a rumour", "The GM owes Lenna something true")
    expect(campaign.reload.gil).to eq(1000 - 100 - 30)
  end

  it "takes rooms for everyone who needs one, in one go, or not at all" do
    bartz.update!(hp: 5)
    lenna.update!(mp: 0)
    campaign.update!(gil: 30)
    expect { campaign.rest_at_inn!(at: town, by: "The GM") }.to raise_error(ArgumentError, /rooms for everyone cost 50/)
    campaign.update!(gil: 60)
    campaign.rest_at_inn!(at: town, by: "The GM")
    expect([ bartz.reload, lenna.reload ].map { |c| campaign.rested?(c) }).to eq([ true, true ])
    expect(campaign.reload.gil).to eq(10)
    expect { campaign.rest_at_inn!(at: town, by: "The GM") }.to raise_error(ArgumentError, /already rested/)
  end

  it "needs the service to be here, and no battle on" do
    bartz.update!(hp: 5)
    empty = Struct.new(:name, :view).new("Nowhere", "services" => [])
    expect { campaign.use_service!("inn", bartz, at: empty, by: "Bartz") }.to raise_error(ArgumentError, /has no inn/)
    start_battle(campaign: campaign)
    expect { campaign.use_service!("inn", bartz, at: town, by: "Bartz") }.to raise_error(ArgumentError, /battle/)
  end
end
