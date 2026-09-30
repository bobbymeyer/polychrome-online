# frozen_string_literal: true

require "rails_helper"

# Players steer: "Where next?" as a vote the GM settles, or the GM just going.
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

  it "lets a player suggest a way: it goes to a vote, and settling it takes the party there" do
    sign_in_as(kim)
    get campaign_table_path(campaign)
    expect(response.body).to include("Where next?", "To Greymere", "To Port", "suggest")
    expect(response.body).not_to include("To The Pass") # blocked

    post campaign_ways_path(campaign), params: { way: "To Greymere" }
    vote = campaign.open_choice
    expect(vote).to be_where_next
    expect(vote.options).to eq([ "To Greymere", "To Port", Campaign::STAY ])
    expect(vote.tally["To Greymere"]).to eq([ "Rook" ])

    sign_out
    sign_in_as(@admin)
    post choice_settlement_path(vote), params: { option: "To Greymere" }
    expect(campaign.reload.current_node).to eq(mere)
    expect(campaign.messages.pluck(:body)).to include("The party chose: To Greymere.", "The party travels from Tule to Greymere.")
  end

  describe "spending the day (Pastime)" do
    before do
      school = world.world_places.create!(name: "Kogen High", kind: "landmark", x: 10, y: 10,
                                          activities: "Attend class (dawn/day, 2): The bell. Maths, then lunch on the roof.\nThe Undertow (night, 4)")
      tule.update!(world_place: school, activities: "Work a shift (day): Aprons, and the till that sticks.")
      campaign.update!(time_of_day: "day")
    end

    it "offers what there is to do here this part of the day, and the table picks it like a way on" do
      sign_in_as(kim)
      get campaign_table_path(campaign)
      expect(response.body).to include("Day in Tule", "Attend class (until night)", "Work a shift (until dusk)", "Or go", "To Greymere")
      expect(response.body).not_to include("The Undertow")

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

    it "won't do what isn't done at this time of day, or somewhere else" do
      expect { campaign.spend_time!(tule, "The Undertow") }.to raise_error(Refusal, /isn't something to do at day/)
      expect { campaign.spend_time!(mere, "Attend class") }.to raise_error(Refusal, /There's no Attend class at Greymere/)
    end

    it "is written by the GM on the map and by the world's author in the atlas" do
      post campaign_table_seat_path(campaign), params: { seat: "gm" }
      get edit_map_node_path(tule)
      expect(response.body).to include("Things to do here", "The setting's, too: Attend class and The Undertow")
      patch map_node_path(tule), params: { map_node: { name: "Tule", kind: "town", activities: "Attend class (day): Cancelled: a free period." } }
      expect(tule.reload.pastimes.map(&:name)).to eq([ "The Undertow", "Attend class" ]) # the GM's replaces the setting's
      expect(tule.pastimes.last.line).to eq("Cancelled: a free period.")

      place = tule.world_place
      patch world_world_place_path(world, place), params: { world_place: { name: place.name, kind: "landmark", activities: "Club (dusk)" } }
      expect(place.reload.activities).to eq("Club (dusk)")
    end

    it "takes a colon inside a name, when no space follows it" do
      tule.update!(activities: "Wait for the 0:13 (night): The last train.")
      expect(tule.pastimes.last).to have_attributes(name: "Wait for the 0:13", times: %w[night], line: "The last train.")
    end

    it "checks how a place's things to do are written" do
      tule.update(activities: "Nap (noon)\n(no name)")
      expect(tule.errors[:activities]).to include("“Nap”: noon isn't a part of the day (dawn, day, dusk, night) or a number of parts",
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
    expect { campaign.ask_where_next! }.to raise_error(Refusal, /nowhere to go/)
  end

  it "holds players' suggestions while the table decides something else, and says so" do
    sign_in_as(kim)
    Message.choice(campaign, options: %w[Yes No]).save!
    get campaign_table_path(campaign)
    expect(response.body).to match(/<button class="menu__item" disabled="disabled" type="submit">\s*To Greymere/)
    expect(response.body).to include("The table is deciding something else first")
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
