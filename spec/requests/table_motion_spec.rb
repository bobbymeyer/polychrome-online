# frozen_string_literal: true

require "rails_helper"

# What the table says before and as things change (docs/DESIGN.md, "Motion with meaning").
RSpec.describe "The table's motion", type: :request do
  let(:world) { base_world }
  let(:gm) { make_user("GM") }
  let(:campaign) { create_campaign(world: world).tap { |c| c.update!(gm: gm) } }
  let!(:rook) { create_character(campaign, name: "Rook", user: gm) }

  before do
    sign_in_as(gm)
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    campaign.set_out!(from_the_setting: true)
  end

  it "says what a way sets off: a night's clocks, a thing to do's outcomes, a journey's clocks" do
    campaign.clocks.create!(name: "The count schemes", segments: 4, triggers: %w[rest], public: true)
    campaign.clocks.create!(name: "The roads close", segments: 4, triggers: %w[travel], public: true)
    campaign.current_node.world_place.update!(activities: "Sweep the yard (any, money 5): Dust.")
    get campaign_table_path(campaign)
    expect(response.body).to include(%(<span class="menu__note">5 gil for the party</span>))
    expect(response.body).to include("the night passes · ticks The count schemes")
    expect(response.body).to include("ticks The roads close")
  end

  it "shows the box a clock is about to fill by itself, to the GM and the table" do
    clock = campaign.clocks.create!(name: "The tide", segments: 4, triggers: %w[dawn], public: true)
    expect(clock.next_tick).to eq("new day")
    get campaign_prep_path(campaign)
    expect(response.body).to include("A dashed box fills by itself")
    expect(response.body).to match(/clock-#{clock.id}".*?<i class=" is-next">/m)
    get campaign_table_path(campaign)
    expect(response.body).to match(/clock-#{clock.id}".*?<i class=" is-next">/m)
  end

  it "arrives on a card: the travel line carries the cue and the place" do
    edge = campaign.current_node.edges.reject(&:blocked?).find { |e| e.state == "open" }
    campaign.travel!(edge)
    line = campaign.messages.where(cue: "arrival").last
    expect(line.data).to include("moved" => true, "place" => campaign.current_node.name, "kind" => campaign.current_node.kind.humanize)
    get campaign_table_path(campaign)
    expect(response.body).to include('data-moment-cue="arrival"')
    # The line carries what the card shows, so the card isn't blank (moment_controller fills it from the line).
    card = Nokogiri::HTML(response.body).at("##{ActionView::RecordIdentifier.dom_id(line)}")["data-chat-line-card-value"]
    expect(JSON.parse(card)).to include("place" => campaign.current_node.name, "kind" => campaign.current_node.kind.humanize)
  end

  it "marks the Now band's state and, on the stage's map, the party's marker, so a change wipes and hops" do
    get campaign_table_path(campaign)
    expect(response.body).to include('data-state="free" data-change="state"')
    campaign.show_map!
    get campaign_table_path(campaign)
    expect(response.body).to include('class="map-party" transform=', 'data-change="marker" data-change-key="party"')
  end

  it "shows the vote filling: pickers as chips, each option's share as a bar" do
    choice = Message.choice(campaign, options: [ "Left", "Right" ]).tap(&:save!)
    choice.picks.create!(character: rook, option: "Left")
    get campaign_table_path(campaign)
    expect(response.body).to include(%(<i class="choice__chip" data-change-key="Rook" aria-hidden="true">R</i>))
    expect(response.body).to include(%(data-change="bar" style="width: 100%"))
    expect(response.body).to include(%(<span data-change="number">1</span> of 1 player has picked))
  end
end
