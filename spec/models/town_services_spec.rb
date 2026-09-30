# frozen_string_literal: true

require "rails_helper"

# A town's inn, temple and guild, and camp on the road: things to do with a
# price and an outcome (Campaign::Services, Outcome).
RSpec.describe "Town services" do
  let(:campaign) { base_world.campaigns.create!(name: "Rust", gil: 1000) }
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let!(:lenna) { create_character(campaign, name: "Lenna") }
  let(:village) { campaign.world.location_templates.find_by!(slug: "village") }
  let(:town) { campaign.locations.create!(location_template: village, seed: 13) }
  let(:tule) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true, location: town) }
  let(:road) { campaign.map_nodes.create!(name: "The Road", kind: "field", x: 300, y: 100, visible: true) }

  before do
    campaign.update!(current_node: tule)
  end

  def labels = campaign.reload.pastimes_here.map { |way| way["label"] }

  it "charges by level, with a floor" do
    expect(campaign.service_price("inn", bartz)).to eq(25) # level 5
    expect(campaign.service_price("temple", bartz)).to eq(100)
    expect(campaign.service_price("guild", bartz)).to eq(30)
  end

  it "offers the town's services as things to do: rooms for everyone, a raising for the KO'd, a rumour" do
    expect(labels).to eq([ "Rooms at Last Light Inn (50 gil, overnight)", "Rumours at Adventurers' Hall (30 gil)" ])
    bartz.update!(hp: 0)
    expect(labels).to include("A raising at Shrine of the Four Winds (100 gil)")

    campaign.take_way!("A raising at Shrine of the Four Winds (100 gil)")
    expect(bartz.reload).to be_conscious
    expect(campaign.messages.last(2).map(&:body)).to eq([ "Tule: A raising at Shrine of the Four Winds (100 gil).", "Bartz is raised, whole again." ])

    campaign.take_way!("Rumours at Adventurers' Hall (30 gil)")
    expect(campaign.messages.last.body).to eq("The party listens, but hears nothing new.")
    expect(campaign.reload.gil).to eq(1000 - 100 - 30)
  end

  it "takes rooms for everyone, the KO'd back on their feet, and the night passes and the rest clocks tick" do
    clock = campaign.clocks.create!(name: "The count schemes", segments: 4, triggers: %w[rest])
    campaign.update!(time_of_day: "dusk", gil: 30)
    bartz.update!(hp: 0)
    lenna.update!(hp: 5, mp: 0)
    expect { campaign.take_way!("Rooms at Last Light Inn (50 gil, overnight)") }.to raise_error(Refusal, /costs 50 gil/)

    campaign.update!(gil: 60)
    campaign.take_way!("Rooms at Last Light Inn (50 gil, overnight)")
    expect([ bartz.reload.current_hp, lenna.reload.current_mp ]).to eq([ bartz.stats["max_hp"], lenna.stats["max_mp"] ])
    expect(campaign.reload).to have_attributes(gil: 10, day: 2, time_of_day: "dawn")
    expect(clock.reload.filled).to eq(1)
    expect(campaign.messages.pluck(:body)).to include("Everyone sleeps in a bed: full HP and MP. Bartz is back on their feet.")
  end

  it "shuts what a mode shuts, and deals nothing to a party the town shuns" do
    town.add_mode!("name" => "Burning", "closed" => %w[inn])
    town.switch_mode!("burning")
    expect(labels).to eq([ "Rumours at Adventurers' Hall (30 gil)", "Make camp (overnight)" ]) # no inn: camp
    allow_any_instance_of(Location).to receive(:shuns_party?).and_return(true) # they won't deal with the party
    expect(labels).to eq([ "Make camp (overnight)" ])
  end

  it "makes camp on the road without raising the fallen, and says what would" do
    campaign.update!(current_node: road)
    expect(labels).to eq([ "Make camp (overnight)" ])
    bartz.update!(hp: 0)
    lenna.update!(hp: 5)
    campaign.take_way!("Make camp (overnight)")
    expect(campaign.messages.pluck(:body)).to include(
      "The party rests. Everyone standing is back to full HP, and half their MP. Bartz is still KO'd. It takes a bed at an inn, a temple, or Phoenix Down."
    )
    expect([ bartz.reload.conscious?, lenna.reload.current_hp ]).to eq([ false, lenna.stats["max_hp"] ])
  end

  it "needs no battle on" do
    start_battle(campaign: campaign)
    expect { campaign.take_way!("Rumours at Adventurers' Hall (30 gil)") }.to raise_error(Refusal, /battle/)
  end
end
