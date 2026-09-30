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
    post map_node_modes_path(town.map_node), params: { mode: { name: "Burning", line: "Smoke over the rooftops: Tule is burning.",
                                                         description: "Half the market is ash.", music: "battle",
                                                         encounters: "grasslands", closed: %w[shop inn] } }
  end

  it "prepares a mode, sets it off for the table, and puts it back" do
    prepare_burning
    expect(town.map_node.reload.modes.sole).to have_attributes(key: "burning", closed: %w[shop inn], music: "battle")
    get location_path(town)
    expect(response.body).to include("GM: modes", "Burning", "Set it off")

    patch map_node_current_mode_path(town.map_node), params: { key: "burning" }
    expect(town.map_node.reload.current_mode["name"]).to eq("Burning")
    expect(campaign.messages.last.body).to eq("Smoke over the rooftops: Tule is burning.")
    get location_path(town)
    expect(response.body).to include("location-mode", "Half the market is ash.", "Shut: Shop and Inn")

    delete map_node_current_mode_path(town.map_node), params: { line: "The fires are out." }
    expect(town.map_node.reload.current_mode).to be_nil
    expect(campaign.messages.last.body).to eq("The fires are out.")
  end

  it "follows the hours: a place by night comes on at night and goes at dawn, on top of a mode set off, which outlasts them" do
    post map_node_modes_path(town.map_node), params: { mode: { name: "By night", line: "The shutters come down. Under the platform, the Undertow wakes.",
                                                         closed: %w[shop], times: [ "", "night" ] } }
    expect(town.map_node.reload.modes.sole).to have_attributes(times: %w[night], timed?: true)
    get location_path(town)
    expect(response.body).to include("by itself: night")

    campaign.update!(current_node: node, time_of_day: "dusk")
    campaign.pass_time!(1)
    expect(town.reload.modes_on.map(&:name)).to eq([ "By night" ])
    expect(town.map_node.current_mode).to be_nil # the calendar's, not the table's
    expect(town.map_node.shut_by("shop")).to be_present
    expect(campaign.messages.pluck(:body)).to include("The shutters come down. Under the platform, the Undertow wakes.")

    campaign.pass_time!(1) # dawn
    expect(town.reload.modes_on).to be_empty

    prepare_burning
    patch map_node_current_mode_path(town.map_node), params: { key: "burning" }
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
    town.map_node.add_mode!("name" => "Snowbound", "line" => "Snow to the sills.", "times" => %w[winter], "closed" => %w[pastimes],
                   "activities" => "Build a snow fort (2): It lasts till the thaw.")
    town.map_node.add_mode!("name" => "Market", "times" => [ "market day" ], "closed" => %w[inn])
    expect { town.map_node.add_mode!("name" => "Monsoon", "times" => %w[monsoon]) }.to raise_error(ActiveRecord::RecordInvalid, /monsoon isn't in/)

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

  it "says how it is on arrival: the place's modes, a landmark's too, and as night falls where the party is" do
    shrine = world.world_places.create!(name: "Old Shrine", kind: "landmark", x: 9, y: 9, night_line: "Foxfire between the torii.")
    Atlas.new(campaign).bring_in_places!([ shrine ]) # a landmark's night line is a mode like a town's
    lantern = campaign.map_nodes.find_by!(world_place: shrine)
    expect(lantern.modes.sole).to have_attributes(name: "By night", times: %w[night])
    town.map_node.add_mode!("name" => "By night", "line" => "The shutters come down.", "times" => %w[night])
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
    expect(station.map_node.modes.sole).to have_attributes(name: "By night", times: %w[night], line: "The last train leaves. Something else arrives.")
  end

  it "shuts its services, changes the music and has trouble waiting while it lasts" do
    prepare_burning
    town.map_node.reload.switch_mode!("burning")
    campaign.place_party!(node)
    expect(campaign.reload.scene).to eq("battle")
    expect(campaign.reload.pastimes_here.map { |way| way["label"] }.grep(/\ARooms at/)).to be_empty # the inn is shut: camp

    expect { campaign.buy!(world.items.find_by!(slug: "potion"), 1, at: town, by: "Rook") }.to raise_error(Refusal, /shop is shut/)

    campaign.place_party!(road)
    edge = campaign.map_edges.create!(from_node: road, to_node: node.reload)
    campaign.reload.travel!(edge)
    expect(campaign.reload.pending_encounter).to include("table" => "Tule: Burning")
  end

  it "can be the ending of a scene" do
    prepare_burning
    post campaign_scenes_path(campaign), params: { scene: { name: "The raid", script: "Narrator: Torches in the dark.", ending: "mode",
                                                           mode_choice: "#{node.id}|#{town.map_node.modes.find_by!(key: 'burning').id}" } }
    scene = campaign.scenes.last
    expect(scene).to have_attributes(ending: "mode", map_node_id: node.id, mode: have_attributes(key: "burning"))
    expect(scene.summary).to include("then Tule: Burning")
    scene.play!
    expect(town.map_node.reload.current_mode["key"]).to eq("burning")
  end

  it "shows a in_mode place on the map" do
    prepare_burning
    town.map_node.reload.switch_mode!("burning")
    get campaign_map_path(campaign)
    expect(response.body).to include("has-mode", "map-node__mode")
  end

  it "gives any place modes, a landmark too: prepared and set off from the map" do
    shrine = campaign.map_nodes.create!(name: "Old Shrine", kind: "landmark", x: 400, y: 400, visible: true, activities: "Pray (day): Quiet.")
    get edit_map_node_path(shrine)
    expect(response.body).to include("GM: modes", "Prepare the mode")
    post map_node_modes_path(shrine), params: { mode: { name: "Festival", line: "Lanterns on every step.", closed: %w[pastimes],
                                                         activities: "Catch a goldfish: Two, in a bag." } }
    expect(response).to redirect_to(campaign_map_path(campaign))
    patch map_node_current_mode_path(shrine), params: { key: "festival" }
    expect(shrine.reload.current_mode.name).to eq("Festival")
    expect(campaign.messages.last.body).to eq("Lanterns on every step.")
    expect(shrine.pastimes.reject(&:service).map(&:name)).to eq([ "Catch a goldfish" ])

    get campaign_map_path(campaign)
    expect(response.body).to include('class="map-node__mode"', "Festival")
    delete map_node_current_mode_path(shrine)
    expect(shrine.reload.current_mode).to be_nil
  end

  it "keeps what points at a mode honest when the mode or the place goes" do
    burning = town.map_node.add_mode!("name" => "Burning")
    clock = campaign.clocks.create!(name: "Fire spreads", segments: 4, mode: burning)
    scene = campaign.scenes.create!(name: "Arson", script: "Narrator: Fire!", ending: "mode", map_node: node, mode: burning)
    art = town.mode_arts.create!(mode: burning)
    town.map_node.switch_mode!("burning")

    town.map_node.remove_mode!("burning")
    expect(town.map_node.reload.current_mode).to be_nil
    expect([ clock.reload.mode, scene.reload.mode ]).to eq([ nil, nil ])
    expect(ModeArt.exists?(art.id)).to be(false)

    town.map_node.add_mode!("name" => "Festival")
    town.map_node.switch_mode!("festival")
    expect { town.destroy! }.not_to change(Mode, :count) # the modes are the place's, on the map
    expect { node.destroy! }.to change(Mode, :count).by(-1)
  end
end
