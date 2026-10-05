# frozen_string_literal: true

require "rails_helper"

# Players steer when asked: "Where next?" is a vote the GM opens and settles, or the GM just goes.
RSpec.describe "Where next", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road", gm: @admin) }
  let(:kim) { make_user("Kim") }
  let!(:rook) { create_character(campaign, name: "Rook", user: kim) }
  let(:tule) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 0, y: 0, visible: true) }
  let(:mere) { campaign.map_nodes.create!(name: "Greymere", kind: "wilds", x: 100, y: 0, visible: true) }
  let(:port) { campaign.map_nodes.create!(name: "Port", kind: "town", x: 0, y: 100, visible: true) }
  let(:pass) { campaign.map_nodes.create!(name: "The Pass", kind: "landmark", x: 200, y: 200, visible: true) }

  before do
    campaign.map_edges.create!(from_node: tule, to_node: mere, state: "open")
    campaign.map_edges.create!(from_node: tule, to_node: port, state: "open")
    campaign.map_edges.create!(from_node: tule, to_node: pass, state: "blocked")
    campaign.update!(current_node: tule)
  end

  it "lets the GM ask about anywhere on a map, each a journey by road, and settling it takes the party all the way" do
    far = campaign.map_nodes.create!(name: "Far Hold", kind: "town", x: 300, y: 0, visible: true)
    campaign.map_edges.create!(from_node: mere, to_node: far, state: "open", duration: 2)
    campaign.map_nodes.create!(name: "Nowhere", kind: "wilds", x: 500, y: 500, visible: true) # no road: not on the ballot
    campaign.map_nodes.create!(name: "Unknown", kind: "wilds", x: 600, y: 600, visible: false)

    sign_in_as(@admin)
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    campaign.call_controls!("travel")
    expect(campaign.reload).to be_map_on_stage # calling travel puts the map on the stage: the asking is done from it
    get campaign_table_path(campaign)
    sheet = Nokogiri::HTML(response.body).at("#table_map .map-sheet[data-controller=map-ask]")
    expect(sheet).to be_present
    expect(response.body).not_to include("Ask about somewhere further") # no form under the ways
    expect(sheet.at("a.map-node__ask[data-node-name='Far Hold']")["data-way-label"]).to eq("To Far Hold (3 parts of a day)")
    expect(sheet.at("a.map-node__ask[data-node-name='Far Hold']")["data-journey"]).to eq("3 parts of a day")
    expect(sheet.at("a.map-node__ask[data-node-name='Nowhere']")["data-way-label"]).to be_nil # no road
    expect(sheet.at("a.map-node__ask[data-node-name='Tule']")).to be_nil # where the party is
    expect(sheet.at(".map-sheet__ask-all").text).to eq("Ask the table: anywhere on #{campaign.root_map.name}")
    expect(sheet.at(".map-ask button[data-map-ask-target=go]").text).to eq("Go")

    # Pressing a place: Go takes the party there, road by road.
    post campaign_ways_path(campaign), params: { to: far.id, go: 1 }
    expect(campaign.reload.current_node).to eq(far)
    campaign.update!(current_node: tule)

    post campaign_ways_path(campaign), params: { scope: "map", map_id: campaign.root_map.id }
    vote = campaign.open_choice
    expect(vote).to be_where_next
    expect(vote.options).to eq([ "To Far Hold (3 parts of a day)", "To Greymere (a part of a day)", "To Port (a part of a day)", "Stay here" ])
    expect(vote.data["moves"]["To Far Hold (3 parts of a day)"]).to eq("to" => far.id)
    expect(vote.data["scope"]).to eq("map")

    vote.settle!("To Far Hold (3 parts of a day)")
    expect(campaign.reload.current_node).to eq(far)
    expect(mere.reload).to be_visible # passed through on the way
    expect(campaign.messages.chronological.map(&:body)).to include(/Far Hold/)
  end

  it "lets the GM put a choice between named places, and refuses a ballot too long to read" do
    sign_in_as(@admin)
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    post campaign_ways_path(campaign), params: { scope: "places", places: [ mere.id, port.id, pass.id ] } # the pass is behind a blocked road
    vote = campaign.open_choice
    expect(vote.options).to eq([ "To Greymere (a part of a day)", "To Port (a part of a day)", "Stay here" ])
    vote.destroy!

    many = (1..17).map { |i| campaign.map_nodes.create!(name: "Stop #{i}", kind: "field", x: 10 * i, y: 50, visible: true) }
    many.each { |stop| campaign.map_edges.create!(from_node: tule, to_node: stop) }
    expect { campaign.ask_where_next!(scope: "map", map: campaign.root_map) }.to raise_error(Refusal, /too many places/)
    expect(campaign.ask_where_next!(scope: "places", places: many.first(16)).options.size).to eq(17)
  end

  it "stops a long journey where something waits on the road, for the GM's call" do
    far = campaign.map_nodes.create!(name: "Far Hold", kind: "town", x: 300, y: 0, visible: true)
    beyond = campaign.map_nodes.create!(name: "Beyond", kind: "landmark", x: 400, y: 0, visible: true)
    campaign.map_edges.create!(from_node: mere, to_node: far, state: "dangerous", encounter_table: world.encounter_tables.first)
    campaign.map_edges.create!(from_node: far, to_node: beyond, state: "open")
    campaign.travel_to!(beyond)
    expect(campaign.reload.current_node).to eq(far) # met something on the dangerous road: the party stops there
    expect(campaign.pending_encounter).to be_present
    expect { campaign.travel_to!(beyond) }.to raise_error(Refusal) # until the GM calls it
    campaign.wave_off_encounter!
    expect(campaign.reload.travel_to!(beyond)).to eq(beyond)
    expect { campaign.travel_to!(beyond) }.to raise_error(Refusal, /already at Beyond/)
    expect { campaign.travel_to!(pass) }.to raise_error(Refusal, /No open road/)
  end

  it "puts a rolled encounter first: the Now line says so, and nobody goes on until the GM calls it" do
    campaign.update!(pending_encounter: { "monsters" => { "goblin" => 2 }, "table" => "The road" })
    sign_in_as(kim)
    get campaign_table_path(campaign)
    now = Nokogiri::HTML(response.body).at("#table_now").text.squish
    expect(now).to include("Encounter! 2 × Goblin.", "The GM calls it: fight, or wave it off.")
    expect(response.body).not_to include(%(pick-row__cost">suggest))
    expect { campaign.ask_where_next! }.to raise_error(Refusal, /GM calls it/)
    sign_out
    sign_in_as(@admin)
    get campaign_table_path(campaign)
    frame = Nokogiri::HTML(response.body).at("turbo-frame#forecast")
    expect(frame["src"]).to include("/forecast") # the odds load with the panel (a lazy frame never asked)
    expect(frame["loading"]).to be_nil
    expect { campaign.take_way!("To Greymere") }.to raise_error(Refusal, /GM calls it/)

    campaign.wave_off_encounter!
    campaign.reload.take_way!("To Greymere")
    expect(campaign.current_node).to eq(mere)
  end

  it "takes a Where next? off the table once time passes, since what it offered was for then" do
    vote = campaign.ask_where_next!
    expect(campaign.open_choice).to eq(vote)
    campaign.pass_time!(1)
    expect(campaign.reload.open_choice).to be_nil
    expect(Message.exists?(vote.id)).to be(false)
    expect(campaign.ask_where_next!.options).to include(Campaign::STAY) # asked again, with what there is now
  end

  it "offers nothing until the GM calls travel; then everyone has the ways, and a player's suggestion opens the vote" do
    sign_in_as(kim)
    get campaign_table_path(campaign)
    expect(Nokogiri::HTML(response.body).at("#table_ways").key?("hidden")).to be(true) # talk: nothing to pick
    expect(response.body).to include("The GM has the floor.")
    expect(response.body).not_to include("To Greymere", %(pick-row__cost">suggest))
    post campaign_ways_path(campaign), params: { way: "To Greymere" }
    expect(response).to have_http_status(:forbidden) # not while the table is talking
    expect(campaign.open_choice).to be_nil
    patch campaign_controls_path(campaign), params: { kind: "travel" }
    expect(response).to have_http_status(:forbidden) # the GM calls it
    expect(campaign.reload.controls).to eq("talk")
    sign_out

    sign_in_as(@admin)
    get campaign_table_path(campaign)
    expect(Nokogiri::HTML(response.body).at("#table_ways").key?("hidden")).to be(true) # the GM has no menu either
    controls = Nokogiri::HTML(response.body).css("#table_now .controls-call button")
    expect(controls.map(&:text)).to eq([ "Talk", "Move", "Do", "Scene", "Check", "Fight", "GM" ])
    expect(controls.map { |b| b["aria-pressed"] }).to eq(%w[true false false false false false false])
    expect(controls.map { |b| b["disabled"] }).to all(be_nil) # there's always the night to make camp
    patch campaign_controls_path(campaign), params: { kind: "travel" }
    expect(campaign.reload).to be_travelling
    get campaign_table_path(campaign)
    expect(response.body).to include("To Greymere", "To Port", "Put it to the table")
    expect(response.body[/<section class="window table-ways.*?<\/section>/m]).not_to include("<h2") # the pressed control is the title
    expect(response.body).not_to include("To The Pass") # blocked
    patch campaign_controls_path(campaign), params: { kind: "dance" }
    expect(flash[:alert]).to eq("There's no such thing to call at the table")
    sign_out

    sign_in_as(kim)
    get campaign_table_path(campaign)
    expect(response.body).to include("Where next?", "Say where you'd go", "To Greymere", "To Port", %(pick-row__cost">suggest))
    rows = Nokogiri::HTML(response.body).css("#table_ways table.pick-table[data-controller=pick-table] tr.pick-row")
    expect(rows.map { |row| row.at(".pick-row__act").text }).to eq([ "To Greymere", "To Port" ]) # one way a row, the row the control
    post campaign_ways_path(campaign), params: { way: "To Greymere" }
    vote = campaign.open_choice
    expect(vote).to be_where_next
    expect(vote.options).to eq([ "To Greymere", "To Port", Campaign::STAY ]) # the roads: camp is a thing to do here
    expect(vote.tally["To Greymere"]).to eq([ "Rook" ])
    expect(vote.body).to eq("Where next? 3 ways to choose from.") # the ways are in the panel, not the log

    # Voting, the player sees the ways once: in the vote, not in Where next as well.
    get campaign_table_path(campaign)
    expect(response.body).to include("What will the party do?", "To Greymere")
    expect(response.body).not_to include(%(pick-row__cost">suggest))
    sign_out

    sign_in_as(@admin)
    # The GM has the vote, and under it a small way straight there instead of a second Where next.
    get campaign_table_path(campaign)
    ways = Nokogiri::HTML(response.body).at("#table_ways")
    expect(ways.text).to include("Or go straight there, without the vote", "To Greymere", "Going now ends the vote.")
    expect(ways.text).not_to include("Where next?", "Put it to the table")
    post choice_settlement_path(vote), params: { option: "To Greymere" }
    expect(campaign.reload.current_node).to eq(mere)
    expect(campaign.messages.pluck(:body)).to include("The party chose: To Greymere.", "The party travels from Tule to Greymere.")
    expect(campaign).to be_travelling # until the GM says otherwise
  end

  it "offers what fits the controls: roads in travel, things to do here in doing, all of them to a plain ask" do
    tule.update!(activities: "Work a shift (day): Aprons.")
    campaign.update!(time_of_day: "day")
    expect(campaign.ways_offered).to eq([])
    campaign.call_controls!("travel")
    expect(campaign.ways_offered.map { |w| w["label"] }).to eq([ "To Greymere", "To Port" ])
    expect(campaign.ask_where_next!.options).to eq([ "To Greymere", "To Port", Campaign::STAY ])
    campaign.open_choice.destroy!
    campaign.call_controls!("doing")
    expect(campaign.ways_offered.map { |w| w["label"] }).to eq([ "Work a shift (until dusk)", "Make camp (overnight)" ])
    expect(campaign.ask_where_next!.options).to eq([ "Work a shift (until dusk)", "Make camp (overnight)", Campaign::STAY ])
    campaign.open_choice.destroy!
    campaign.call_controls!("talk")
    expect(campaign.ask_where_next!.options).to eq([ "Work a shift (until dusk)", "To Greymere", "To Port", "Make camp (overnight)", Campaign::STAY ])
    expect { campaign.call_controls!("fight") }.to raise_error(Refusal, /no such thing/)
  end

  describe "spending the day (Pastime)" do
    before do
      school = world.world_places.create!(name: "Kogen High", kind: "landmark", x: 10, y: 10,
                                          activities: "Attend class (dawn/day, 2): The bell. Maths, then lunch on the roof.\nThe Undertow (night, 4)")
      tule.update!(world_place: school, activities: "Work a shift (day): Aprons, and the till that sticks.")
      campaign.update!(time_of_day: "day")
    end

    it "offers what there is to do here this part of the day, once called, and the table picks it like a way on" do
      campaign.call_controls!("doing")
      sign_in_as(kim)
      get campaign_table_path(campaign)
      expect(response.body).to include("Attend class (until night)", "Work a shift (until dusk)", "What will you do here?")
      expect(response.body).not_to include("The Undertow", "To Greymere") # not now; not the roads
      expect(Nokogiri::HTML(response.body).css("#table_ways .pick-table .pick-row").size).to eq(3) # one a row: class, the shift, camp

      post campaign_ways_path(campaign), params: { way: "Attend class (until night)" }
      vote = campaign.open_choice
      expect(vote.options).to start_with("Attend class (until night)", "Work a shift (until dusk)")

      vote.settle!("Attend class (until night)")
      expect(campaign.reload).to have_attributes(day: 1, time_of_day: "night", current_node: tule)
      expect(campaign.messages.pluck(:body)).to include("Tule: Attend class.", "The bell. Maths, then lunch on the roof.", "Night.")

      expect(campaign.ways_on.map { |w| w["label"] }).to include("The Undertow (until night, tomorrow)")
      campaign.take_way!("The Undertow (until night, tomorrow)")
      expect(campaign.reload).to have_attributes(day: 2, time_of_day: "night")
    end

    it "pays off through the archetypes at the next rest" do
      nim = create_character(campaign, name: "Nim", job: world.jobs.find_by!(slug: "thief"))
      ada = create_character(campaign, name: "Ada", job: world.jobs.find_by!(slug: "white_mage"))
      create_character(campaign, name: "Down", job: world.jobs.find_by!(slug: "thief"), hp: 0) # the KO'd earn nothing
      campaign.start_rumour!("The ferryman owes the Vells money.", at: mere) # not heard in Tule yet
      campaign.call_controls!("doing")
      sign_in_as(@admin)
      get campaign_table_path(campaign)
      expect(response.body).to include("At the next rest: Rook, 20 EXP a part; Nim, 40 gil a part; Ada, a rumour")

      campaign.take_way!("Attend class (until night)")
      expect(campaign.reload.spent_parts).to eq(2)
      get campaign_table_path(campaign)
      expect(response.body).to include("2 parts of the day spent so far.")

      gil = campaign.gil
      exp = rook.reload.exp
      campaign.sleep!
      expect(campaign.reload).to have_attributes(gil: gil + 80, spent_parts: 0)
      expect(rook.reload.exp).to eq(exp + 40)
      expect(campaign.messages.pluck(:body)).to include(
        "Rook drills with the watch: 40 EXP.", "Nim comes back with 80 gil and no explanation.",
        "Ada sits with the sick, and hears something: “The ferryman owes the Vells money.”"
      )

      # A rest with nothing done pays nothing.
      expect { campaign.update!(time_of_day: "night") && campaign.sleep! }.not_to(change { campaign.reload.gil })
    end

    it "pays for what it costs and makes happen what it does" do
      tule.update!(activities: "Work a shift (day, 2, money 40): Aprons.\nThe good tea (pay 25, 0, restore 50)\nStudy (day, abp 3)")
      campaign.update!(gil: 20)
      rook.update!(hp: 10)
      expect(campaign.reload.ways_on.map { |w| w["label"] }).to include("Work a shift (until night)", "The good tea (25 gil)", "Study (until dusk)")
      expect { campaign.take_way!("The good tea (25 gil)") }.to raise_error(Refusal, "The party has 20 gil; The good tea costs 25 gil")
      campaign.call_controls!("doing")
      sign_in_as(kim)
      get campaign_table_path(campaign)
      ways = Nokogiri::HTML(response.body).at("#table_ways").text
      expect(ways).to include("Work a shift (until night)")
      expect(ways).not_to include("The good tea") # not offered to players while the purse can't pay

      campaign.take_way!("Work a shift (until night)")
      expect(campaign.reload).to have_attributes(gil: 60, time_of_day: "night")
      expect(campaign.messages.last(4).map(&:body)).to eq([ "Tule: Work a shift.", "Aprons.", "The party: 40 gil.", "Night." ])

      campaign.update!(time_of_day: "day")
      campaign.take_way!("The good tea (25 gil)")
      expect(campaign.reload).to have_attributes(gil: 35, time_of_day: "day") # a moment: no time passes
      expect(rook.reload.current_hp).to eq(10 + (rook.stats["max_hp"] / 2))
      campaign.take_way!("Study (until dusk)")
      expect(campaign.messages.pluck(:body)).to include(a_string_starting_with("The party: 3 ABP. Rook: Knight level"))
    end

    it "won't do what isn't done at this time of day, or somewhere else" do
      expect { campaign.spend_time!(tule, "The Undertow") }.to raise_error(Refusal, /isn't something to do now \(day\)/)
      expect { campaign.spend_time!(mere, "Attend class") }.to raise_error(Refusal, /There's no Attend class at Greymere/)
    end

    it "is written by the GM on the map and by the world's author in the atlas" do
      post campaign_table_seat_path(campaign), params: { seat: "gm" }
      get edit_map_node_path(tule)
      expect(response.body).to include("Things to do here", "The setting's, too: Attend class and The Undertow")
      patch map_node_path(tule), params: { map_node: { name: "Tule", kind: "town", activities: "Attend class (day): Cancelled: a free period." } }
      expect(tule.reload.pastimes.reject(&:service).map(&:name)).to eq([ "The Undertow", "Attend class" ]) # the GM's replaces the setting's
      expect(tule.pastimes.find { |p| p.name == "Attend class" }.line).to eq("Cancelled: a free period.")

      place = tule.world_place
      patch world_world_place_path(world, place), params: { world_place: { name: place.name, kind: "landmark", activities: "Club (dusk)" } }
      expect(place.reload.activities).to eq("Club (dusk)")
    end

    it "takes a colon inside a name, when no space follows it" do
      tule.update!(activities: "Wait for the 0:13 (night): The last train.")
      expect(tule.pastimes.reject(&:service).last).to have_attributes(name: "Wait for the 0:13", times: %w[night], line: "The last train.")
    end

    it "checks how a place's things to do are written" do
      tule.update(activities: "Nap (noon)\n(no name)")
      expect(tule.errors[:activities]).to include(a_string_starting_with("“Nap”: noon isn't in the calendar (a part of the day, a day of the week, a month or a season), a price (pay 20), an outcome"),
                                                  "“(no name)” needs a name before any brackets or colon")
    end
  end

  it "stays put when the party chooses to" do
    vote = campaign.ask_where_next!
    vote.settle!(Campaign::STAY)
    expect(campaign.reload.current_node).to eq(tule)
  end

  it "lets the GM just go, and takes a vote the party moved on from off the table" do
    vote = campaign.ask_where_next!
    post campaign_ways_path(campaign), params: { way: "To Port", go: 1 }
    expect(campaign.reload.current_node).to eq(port)
    expect(Message.exists?(vote.id)).to be(false)
    expect(campaign.open_choice).to be_nil
  end

  it "won't open a vote over another choice, or where there's nowhere to go" do
    Message.choice(campaign, options: %w[Yes No]).save!
    expect { campaign.ask_where_next! }.to raise_error(Refusal, /something else first/)
    campaign.open_choice.settle!("Yes")
    campaign.map_edges.update_all(state: "blocked")
    expect(campaign.ask_where_next!.options).to eq([ "Make camp (overnight)", Campaign::STAY ]) # there's always the night
    campaign.open_choice.settle!(Campaign::STAY)
    campaign.update!(current_node: nil)
    expect { campaign.ask_where_next! }.to raise_error(Refusal, /nowhere to go/)
  end

  it "offers a dungeon's door, then its ways on, naming only rooms the players have seen" do
    cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
    post map_node_location_path(cave_node), params: { location_template_id: world.location_templates.find_by!(slug: "goblin_cave").id }
    cave = cave_node.reload.location
    campaign.update!(current_node: cave_node)
    expect(campaign.ways_on.first).to eq("label" => "Into #{cave.name}", "move" => { "location" => cave.id, "enter" => true })

    vote = campaign.ask_where_next!
    vote.settle!("Into #{cave.name}")
    expect(cave.reload.progress["current"]).to eq(cave.view["entrance"])
    ways, out = campaign.reload.ways_on.partition { |way| way.dig("move", "room") }
    expect(ways).to all(include("move" => include("location" => cave.id, "room" => be_present)))
    expect(out).to eq([ { "label" => "Leave #{cave.name}", "move" => { "location" => cave.id, "leave" => true } } ]) # at the entrance
    ways.each do |way|
      seen = cave.seen_by_players?(way.dig("move", "room"))
      expect(way["label"]).to(seen ? start_with(cave.room(way.dig("move", "room"))["name"]) : start_with("An unexplored way"))
    end
  end

  it "shows the dungeon's floorplan on the maps page and the stage, and tells the GM at the table what waits in each room" do
    cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
    cave = campaign.locations.create!(location_template: world.location_templates.find_by!(slug: "goblin_cave"), seed: 11)
    cave_node.update!(location: cave)
    campaign.update!(current_node: cave_node)
    cave.enter!
    key = cave.add_room!(name: "Vault of the Old Kings", connect: cave.view["entrance"], decision: { "kind" => "treasure", "gil" => 40 })

    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    campaign.call_controls!("travel")
    get campaign_maps_path(campaign)
    floorplan = response.body[/<div id="table_floorplan".*?<\/svg>/m]
    expect(floorplan).to include(cave.name, "Vault of", "the Old", "Kings") # every room, names on as many lines as they need
    get campaign_table_path(campaign)
    expect(response.body).to include('id="table_floorplan"') # calling travel put the map on the stage: inside, the floorplan
    ways = response.body[/<section class="window table-ways".*?<\/section>/m]
    expect(ways).to include(%(<td class="pick-row__cost">treasure</td>))

    campaign.show_map! # inside a dungeon, the stage's map view is its floorplan
    sign_in_as(kim)
    get campaign_table_path(campaign)
    theirs = response.body[/<div id="table_floorplan".*?<\/svg>/m]
    expect(theirs).to include(cave.name)
    expect(theirs).not_to include("Vault of") # not been in: an unexplored way at most
    expect(response.body).not_to include(%(<td class="pick-row__cost">treasure</td>))
    expect(cave.room(key)["name"]).to eq("Vault of the Old Kings")
  end

  it "lets a player pick up treasure in the room the party is in, from the table" do
    cave_node = campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 300, y: 300, visible: true)
    cave = campaign.locations.create!(location_template: world.location_templates.find_by!(slug: "goblin_cave"), seed: 11)
    cave_node.update!(location: cave)
    campaign.update!(current_node: cave_node)
    cave.enter!
    key = cave.add_room!(name: "Vault", connect: cave.view["entrance"], decision: { "kind" => "treasure", "gil" => 40 })

    sign_in_as(kim)
    post location_treasures_path(cave), params: { room: key, return_to: "table" }
    expect(flash[:alert]).to eq("The party isn't in that room")

    cave.move_to!(key)
    get campaign_table_path(campaign)
    expect(response.body).to include("There's treasure in Vault", ">Take it<")
    expect { post location_treasures_path(cave), params: { room: key, return_to: "table" } }.to change { campaign.reload.gil }.by(40)
    expect(response).to redirect_to(campaign_table_path(campaign))
    expect(flash[:notice]).to eq("Found 40 gil in Vault.")
  end
end
