# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Deeds, reputation, leaks and legends", type: :request do
  let!(:world) { base_world }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:campaign) { world.campaigns.create!(name: "Pulp", gm: @admin, gil: 1000) }
  let(:varn_town) { campaign.locations.create!(location_template: village, seed: 11, overrides: { "name" => "Varn" }) }
  let(:tule_town) { campaign.locations.create!(location_template: village, seed: 12, overrides: { "name" => "Tule" }) }
  let!(:varn) { campaign.map_nodes.create!(name: "Varn", kind: "town", x: 100, y: 100, visible: true, location: varn_town) }
  let!(:tule) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 300, y: 100, visible: true, location: tule_town) }
  let!(:road) { campaign.map_edges.create!(from_node: varn, to_node: tule, state: "open") }
  let!(:hero) { campaign.characters.create!(name: "Rook", job: world.jobs.find_by!(slug: "knight"), user: @admin) }
  let(:potion) { world.items.find_by!(slug: "potion") }

  before do
    campaign.update!(current_node: varn)
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
  end

  it "records a deed, and the towns the story reaches think better of the party, and sell cheaper" do
    post campaign_deeds_path(campaign), params: { deed: { body: "Rook pulled the miller's child from the weir.", map_node_id: varn.id, sway: 2 } }
    deed = campaign.deeds.sole
    expect(deed).to have_attributes(day: 1, sway: 2, map_node: varn)
    expect(varn_town.reload.reputation).to eq(2)
    expect(tule_town.reload.reputation).to eq(0)

    campaign.rest!
    expect(tule_town.reload).to have_attributes(reputation: 2, standing: "Welcome")
    expect(campaign.messages.where("body LIKE ?", "In Varn, people are saying%")).to be_empty # they were there
    campaign.travel!(road)
    expect(campaign.messages.where(body: "In Tule, people are saying: “Rook pulled the miller's child from the weir.”")).to exist
    expect(campaign.rumours.sole).to have_attributes(heard_at: tule, heard_day: 2)
    expect(campaign.rumours.sole.rumour_places.pluck(:map_node_id, :day)).to eq([ [ varn.id, 1 ], [ tule.id, 2 ] ])
    expect(campaign.rumours.at(tule)).to eq([ campaign.rumours.sole ])
    expect(tule_town.price_of(potion)).to eq((potion.price * 0.9).round)

    get location_path(tule_town)
    expect(response.body).to include("Tule sees the party as <strong>welcome</strong>")
    get campaign_path(campaign)
    expect(response.body).to include("Deeds", "Rook pulled the miller&#39;s child from the weir.", "Tule: Welcome (+2)")

    campaign.start_rumour!("Wolves at the ford.", at: varn)
    varn.destroy!
    expect(RumourPlace.where(map_node_id: varn.id)).to be_empty
    expect(tule_town.reload.reputation).to eq(2) # the story still got to Tule
  end

  it "has a town that thinks badly enough of the party refuse them, until the GM strikes the deed" do
    stock = { "stock" => [ "potion" ] }
    tule_town.update!(overrides: tule_town.overrides.merge(stock))
    2.times { campaign.record_deed!("Rook burned the Tule granary.", at: tule, sway: -2) }
    expect(tule_town.reload).to have_attributes(reputation: -4, standing: "Unwelcome")
    campaign.update!(current_node: tule)
    expect { campaign.buy!(potion, 1, at: tule_town, by: "Rook") }.to raise_error(Refusal, "Nobody in Tule will deal with the party.")

    struck = campaign.deeds.first
    delete campaign_deed_path(campaign, struck)
    expect(tule_town.reload.reputation).to eq(-2) # the sum of what's left, not a stored number undone
    expect(campaign.rumours.where(deed_id: struck.id)).to be_empty
    expect { campaign.buy!(potion, 1, at: tule_town, by: "Rook") }.not_to raise_error
  end

  it "records beating an antagonist and clearing a dungeon by themselves" do
    battle = campaign.battles.new(world: world, boss: true)
    battle.send(:record_deeds!, { "antagonists" => [ { "name" => "Mara", "fate" => "defeated" }, { "name" => "Gorn", "fate" => "escaped" } ] },
                { hero.battle_unit_id => hero })
    expect(campaign.deeds.pluck(:body, :kind, :sway)).to eq([ [ "Rook defeated Mara for good.", "antagonist", 1 ] ])
  end

  it "lets a secret out overnight, and shows the GM it's going round" do
    secret = campaign.secrets.create!(body: "The miller pays the goblins.", location: varn_town)
    allow(Pointcrawl::Overnight).to receive(:run) { |state, rng| @seen = state; [ rng, [ { "kind" => "leak", "secret" => secret.id, "at" => varn.id } ] ] }
    campaign.rest!
    expect(@seen["secrets"]).to eq([ { "id" => secret.id, "at" => varn.id } ])
    expect(secret.reload.rumour).to have_attributes(body: "The miller pays the goblins.", reached: [ varn.id ])
    expect(campaign.messages.where(body: "In Varn, someone whispers: “The miller pays the goblins.”")).to exist
    expect(secret).not_to be_revealed

    get campaign_path(campaign)
    expect(response.body).to include("got out: it's going round as a rumour, and the party has heard it")
  end

  it "tells the legends: the history the party can know, and their story since; the GM sees the rest" do
    known = world.world_places.create!(name: "Varnhold", kind: "town", x: 100, y: 100, known: true)
    unknown = world.world_places.create!(name: "The Sunk Abbey", kind: "dungeon", x: 500, y: 400)
    Chronicle.new(world).write!
    events = Chronicle.new(world.reload).written_events
    about_unknown = events.find { |e| e["places"] == [ "place-#{unknown.id}" ] }
    about_known = events.find { |e| e["places"] == [ "place-#{known.id}" ] }

    fresh = world.campaigns.create!(name: "Legends", gm: @admin)
    Atlas.new(fresh).bring_in_all!
    fresh.characters.create!(name: "Rook", job: world.jobs.find_by!(slug: "knight"))
    varnhold = fresh.map_nodes.find_by!(name: "Varnhold")
    fresh.record_deed!("Rook climbed the old tower.", at: varnhold, sway: 1)
    fresh.start_rumour!("The abbey bells rang at midnight.", at: varnhold).update!(heard: true, heard_day: 1, heard_at: varnhold)

    post campaign_table_seat_path(fresh), params: { seat: "gm" }
    get campaign_legends_path(fresh)
    expect(response.body).to include("The party's story", "Rook climbed the old tower.", "Long ago", about_known["text"].split(".").first,
                                      about_unknown["text"].split(".").first, "the party doesn't know this yet")

    sign_in_as(make_user("Player"))
    get campaign_legends_path(fresh)
    expect(response.body).to include("Rook climbed the old tower.", about_known["text"].split(".").first)
    expect(response.body).not_to include(about_unknown["text"].split(".").first, "GM:")
    expect(response.body).to include("Heard in Varnhold:", "The abbey bells rang at midnight.")
  end
end
