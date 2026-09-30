# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The world moving overnight (Campaign::Overnight)", type: :request do
  let!(:world) { base_world }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:campaign) { world.campaigns.create!(name: "Pulp", gm: @admin) }
  let(:varn_town) { campaign.locations.create!(location_template: village, seed: 11) }
  let(:tule_town) { campaign.locations.create!(location_template: village, seed: 12) }
  let!(:varn) { campaign.map_nodes.create!(name: "Varn", kind: "town", x: 100, y: 100, visible: true, location: varn_town) }
  let!(:tule) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 300, y: 100, visible: true, location: tule_town) }
  let!(:road) { campaign.map_edges.create!(from_node: varn, to_node: tule, state: "dangerous") }
  let(:hero) { campaign.characters.create!(name: "Rook", job: world.jobs.find_by!(slug: "knight"), user: @admin) }

  before do
    hero
    campaign.update!(current_node: tule)
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
  end

  it "lets a rumour loose, carries it a road a night, and the party hears it where it gets to" do
    post campaign_rumours_path(campaign), params: { rumour: { body: "The mill grinds at night.", origin_id: varn.id } }
    rumour = campaign.rumours.sole
    expect(rumour).to have_attributes(reached: [ varn.id ], heard: false)

    campaign.update!(time_of_day: "night") # a rest from dawn only takes the morning
    rest_the_night(campaign)
    expect(rumour.reload).to have_attributes(reached: [ varn.id, tule.id ], heard: true, age: 1)
    expect(campaign.messages.where(body: "In Tule, people are saying: “The mill grinds at night.”")).to exist

    get campaign_prep_path(campaign)
    expect(response.body).to include("Rumours", "The mill grinds at night.", "the party has heard it")
    delete campaign_rumour_path(campaign, rumour)
    expect(rumour.reload).to be_faded
  end

  it "sells a rumour the party hasn't heard at the guild, and starts one when a place changes" do
    varn_town.map_node.add_mode!("name" => "Burning", "line" => "Smoke over Varn.")
    varn_town.map_node.switch_mode!("burning")
    rumour = campaign.rumours.sole
    expect(rumour).to have_attributes(body: "Smoke over Varn.", reached: [ varn.id ], heard: false)

    # What the guild sells (Campaign::Services).
    expect(Outcome.of("rumour").apply!(campaign, by: "Rook")).to end_with("“Smoke over Varn.”")
    expect(rumour.reload).to be_heard
  end

  it "moves antagonists, loses caravans, shifts prices and ticks clocks as the night says, and tells only the GM" do
    mara = campaign.npcs.create!(name: "Mara", monster: world.monsters.find_by!(slug: "goblin_chief"), location: varn_town, escapes: 1)
    clock = campaign.clocks.create!(name: "The feud comes to blood", segments: 6, triggers: [ "now_and_then" ])
    night = [ { "kind" => "clock", "clock" => clock.id },
              { "kind" => "moved", "npc" => mara.id, "name" => "Mara", "from" => varn.id, "to" => tule.id },
              { "kind" => "caravan", "from" => varn.id, "to" => tule.id },
              { "kind" => "price", "place" => tule.id, "shift" => 15 } ]
    allow(Pointcrawl::Overnight).to receive(:run) { |world_state, rng| @seen = world_state; [ rng + 1, night ] }

    campaign.update!(time_of_day: "night")
    rest_the_night(campaign)
    expect(@seen).to include("clocks" => [ clock.id ], "antagonists" => [ { "id" => mara.id, "name" => "Mara", "at" => varn.id } ])
    expect(@seen["places"]).to include({ "id" => tule.id, "name" => "Tule", "town" => true, "settled" => true, "lair" => false })
    expect(clock.reload.filled).to eq(1)
    expect(mara.reload.location).to eq(tule_town)
    expect(tule_town.reload.prices).to eq(15)
    expect(campaign.rumours.pluck(:body)).to contain_exactly("Mara was seen in Tule.", "A caravan on the road between Varn and Tule was attacked.")
    expect(campaign.messages.where(body: "In Tule, people are saying: “Mara was seen in Tule.”")).to exist

    note = campaign.messages.find_by!(scope: "gm")
    expect(note.body).to start_with("Overnight: The feud comes to blood moved on (1 of 6).").and include("Mara went from Varn to Tule.", "Prices in Tule: +15%.")
    expect(Message.visible_to(campaign, Seat.of(hero))).not_to include(note)
    expect(Message.visible_to(campaign, Seat.gm)).to include(note)

    potion = world.items.find_by!(slug: "potion")
    expect(tule_town.price_of(potion)).to eq((potion.price * 1.15).round)
  end

  it "has the party hear what's being said on arriving somewhere, once" do
    campaign.start_rumour!("Wolves on the north road.", at: varn)
    campaign.travel!(road)
    said = "In Varn, people are saying: “Wolves on the north road.”"
    expect(campaign.messages.where(body: said).count).to eq(1)
    campaign.place_party!(varn)
    expect(campaign.messages.where(body: said).count).to eq(1)
  end

  it "hears at a landmark what was set loose there, but not what's only passing through" do
    school = campaign.map_nodes.create!(name: "Kogen High", kind: "landmark", x: 200, y: 200, visible: true)
    campaign.map_edges.create!(from_node: tule, to_node: school, duration: 0)
    campaign.start_rumour!("The rooftop door is never locked.", at: school)
    passing = campaign.start_rumour!("Wolves on the north road.", at: tule)
    passing.reach!(school, day: campaign.day)
    campaign.place_party!(school)
    campaign.pass_time!(1)
    expect(campaign.messages.pluck(:body)).to include("In Kogen High, people are saying: “The rooftop door is never locked.”")
    expect(campaign.messages.pluck(:body)).not_to include(a_string_including("In Kogen High, people are saying: “Wolves"))
  end
end
