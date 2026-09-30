# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Location modes", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Pulp", gm: @admin) }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:town) { campaign.locations.create!(location_template: village, seed: 11) }
  let!(:node) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true, location: town) }
  let(:road) { campaign.map_nodes.create!(name: "Road", kind: "field", x: 300, y: 100, visible: true) }
  let(:hero) { campaign.characters.create!(name: "Rook", job: world.jobs.find_by!(slug: "knight"), starting_level: 10) }

  before { post campaign_table_seat_path(campaign), params: { seat: "gm" } }

  def prepare_burning
    post location_modes_path(town), params: { mode: { name: "Burning", line: "Smoke over the rooftops: Tule is burning.",
                                                         description: "Half the market is ash.", music: "battle",
                                                         encounters: "grasslands", closed: %w[shop inn] } }
  end

  it "prepares a mode, sets it off for the table, and puts it back" do
    prepare_burning
    expect(town.reload.modes.sole).to have_attributes(key: "burning", closed: %w[shop inn], music: "battle")
    get location_path(town)
    expect(response.body).to include("GM: modes", "Burning", "Set it off")

    patch location_current_mode_path(town), params: { key: "burning" }
    expect(town.reload.current_mode["name"]).to eq("Burning")
    expect(campaign.messages.last.body).to eq("Smoke over the rooftops: Tule is burning.")
    get location_path(town)
    expect(response.body).to include("location-mode", "Half the market is ash.", "Shut: Shop and Inn")

    delete location_current_mode_path(town), params: { line: "The fires are out." }
    expect(town.reload.current_mode).to be_nil
    expect(campaign.messages.last.body).to eq("The fires are out.")
  end

  it "follows the hours: a place by night comes on at night and goes at dawn, on top of a mode set off, which outlasts them" do
    post location_modes_path(town), params: { mode: { name: "By night", line: "The shutters come down. Under the platform, the Undertow wakes.",
                                                         closed: %w[shop], times: [ "", "night" ] } }
    expect(town.reload.modes.sole).to have_attributes(times: %w[night], timed?: true)
    get location_path(town)
    expect(response.body).to include("by itself: night")

    campaign.update!(current_node: node, time_of_day: "dusk")
    campaign.pass_time!(1)
    expect(town.reload.modes_on.map(&:name)).to eq([ "By night" ])
    expect(town.current_mode).to be_nil # the calendar's, not the table's
    expect(town.service_closed?("shop")).to be(true)
    expect(campaign.messages.pluck(:body)).to include("The shutters come down. Under the platform, the Undertow wakes.")

    campaign.pass_time!(1) # dawn
    expect(town.reload.modes_on).to be_empty

    prepare_burning
    patch location_current_mode_path(town), params: { key: "burning" }
    campaign.pass_time!(3) # to night
    expect(town.reload.modes_on.map(&:name)).to eq([ "Burning", "By night" ]) # the fire doesn't go out at nightfall
    campaign.pass_time!(1)
    expect(town.reload.modes_on.map(&:name)).to eq([ "Burning" ])
  end

  it "comes on when the calendar says, several at once, with things to do of their own" do
    world.update!(calendar: { periods: "Morning, Evening, Late night", dark: "Late night", weekdays: "Weekday, Market day",
                              months: "Thaw (2, Spring)\nFrost (2, Winter)" })
    campaign.update!(current_node: node, time_of_day: "Morning")
    campaign.map_nodes.find(node.id).update!(activities: "Browse the stalls (market day)\nSkate the millpond (winter): Round and round.")
    town.add_mode!("name" => "Snowbound", "line" => "Snow to the sills.", "times" => %w[winter], "closed" => %w[pastimes],
                   "activities" => "Build a snow fort (2): It lasts till the thaw.")
    town.add_mode!("name" => "Market", "times" => [ "market day" ], "closed" => %w[inn])
    expect { town.add_mode!("name" => "Monsoon", "times" => %w[monsoon]) }.to raise_error(ActiveRecord::RecordInvalid, /monsoon isn't in/)

    # Day 1: a weekday in Thaw. Day 2: market day. Day 3: a weekday in Frost.
    expect(town.reload.modes_on).to be_empty
    expect(campaign.reload.pastimes_here.map { |w| w["label"] }.grep_v(/overnight/)) # the inn, or camp, aside.to eq([])
    campaign.pass_time!(3)
    expect(town.reload.modes_on.map(&:name)).to eq([ "Market" ])
    expect(town.shut_by("inn").name).to eq("Market")
    expect(campaign.reload.pastimes_here.map { |w| w["label"] }.grep_v(/overnight/)).to eq([ "Browse the stalls (until Evening)" ])
    campaign.pass_time!(3)
    expect(campaign.messages.pluck(:body)).to include("Snow to the sills.")
    expect(town.reload.modes_on.map(&:name)).to eq([ "Snowbound" ])
    # Snowbound shuts the usual things to do (skating too) and has its own.
    expect(campaign.reload.pastimes_here.map { |w| w["label"] }.grep_v(/overnight/)).to eq([ "Build a snow fort (until Late night)" ])
    campaign.pass_time!(3)
    expect(town.reload.modes_on.map(&:name)).to eq([ "Snowbound", "Market" ])

    get location_path(town)
    expect(response.body).to include("Snowbound", "Market", "Shut: Things to do.")
  end

  it "says how it is on arrival: the place's modes, and a landmark's night line after dark" do
    shrine = world.world_places.create!(name: "Old Shrine", kind: "landmark", x: 9, y: 9, night_line: "Foxfire between the torii.")
    lantern = campaign.map_nodes.create!(name: "Old Shrine", kind: "landmark", x: 9, y: 9, visible: true, world_place: shrine)
    town.add_mode!("name" => "By night", "line" => "The shutters come down.", "times" => %w[night])
    campaign.update!(time_of_day: "night")
    campaign.place_party!(node)
    expect(campaign.messages.last(2).map(&:body)).to eq([ "The party is at #{node.name}.", "The shutters come down." ])
    campaign.place_party!(lantern)
    expect(campaign.messages.last.body).to eq("Foxfire between the torii.")

    campaign.update!(time_of_day: "dusk")
    campaign.pass_time!(1) # night falls at the shrine
    expect(campaign.messages.where(body: "Foxfire between the torii.").count).to eq(2)
  end

  it "comes from the atlas: a place's night line is a mode that comes on at night" do
    place = world.world_places.create!(name: "Tsukiura Station", kind: "town", x: 5, y: 5, location_template: village,
                                       night_line: "The last train leaves. Something else arrives.")
    fresh = world.campaigns.create!(name: "Night Shift", gm: @admin)
    Atlas.new(fresh).bring_in_places!([ place ])
    station = fresh.map_nodes.find_by!(world_place: place).location
    expect(station.modes.sole).to have_attributes(name: "By night", times: %w[night], line: "The last train leaves. Something else arrives.")
  end

  it "shuts its services, changes the music and has trouble waiting while it lasts" do
    prepare_burning
    town.reload.switch_mode!("burning")
    campaign.place_party!(node)
    expect(campaign.reload.scene).to eq("battle")
    expect(campaign.reload.pastimes_here.map { |way| way["label"] }.grep(/\ARooms at/)).to be_empty # the inn is shut: camp

    expect { campaign.buy!(world.items.find_by!(slug: "potion"), 1, at: town, by: "Rook") }.to raise_error(Refusal, /shop is shut/)

    campaign.place_party!(road)
    edge = campaign.map_edges.create!(from_node: road, to_node: node)
    campaign.reload.travel!(edge)
    expect(campaign.reload.pending_encounter).to include("table" => "Tule: Burning")
  end

  it "can be the ending of a scene" do
    prepare_burning
    post campaign_scenes_path(campaign), params: { scene: { name: "The raid", script: "Narrator: Torches in the dark.", ending: "mode",
                                                           mode_choice: "#{node.id}|#{town.modes.find_by!(key: 'burning').id}" } }
    scene = campaign.scenes.last
    expect(scene).to have_attributes(ending: "mode", map_node_id: node.id, location_mode: have_attributes(key: "burning"))
    expect(scene.summary).to include("then Tule: Burning")
    scene.play!
    expect(town.reload.current_mode["key"]).to eq("burning")
  end

  it "shows a in_mode place on the map" do
    prepare_burning
    town.reload.switch_mode!("burning")
    get campaign_map_path(campaign)
    expect(response.body).to include("has-mode", "map-node__mode")
  end

  it "keeps what points at a mode honest when the mode or the place goes" do
    burning = town.add_mode!("name" => "Burning")
    clock = campaign.clocks.create!(name: "Fire spreads", segments: 4, location_mode: burning)
    scene = campaign.scenes.create!(name: "Arson", script: "Narrator: Fire!", ending: "mode", map_node: node, location_mode: burning)
    art = town.mode_arts.create!(location_mode: burning)
    town.switch_mode!("burning")

    town.remove_mode!("burning")
    expect(town.reload.current_mode).to be_nil
    expect([ clock.reload.location_mode, scene.reload.location_mode ]).to eq([ nil, nil ])
    expect(ModeArt.exists?(art.id)).to be(false)

    town.add_mode!("name" => "Festival")
    town.switch_mode!("festival")
    expect { town.destroy! }.to change(LocationMode, :count).by(-1)
  end
end
