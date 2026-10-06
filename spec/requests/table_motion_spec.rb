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
    sit(campaign, "gm")
    campaign.set_out!(from_the_setting: true)
  end

  it "says what a way sets off: a night's clocks, a thing to do's outcomes, a journey's clocks" do
    campaign.clocks.create!(name: "The count schemes", segments: 4, triggers: %w[rest], public: true)
    campaign.clocks.create!(name: "The roads close", segments: 4, triggers: %w[travel], public: true)
    campaign.current_node.world_place.update!(activities: "Sweep the yard (any, money 5): Dust.")
    campaign.call_controls!("doing") # the things to do here, with what each sets off
    get campaign_table_path(campaign)
    expect(page.css("span.pick-row__note").map(&:text)).to include("5 gil for the party")
    expect(response.body).to include("the night passes · ticks The count schemes")
    campaign.call_controls!("travel") # the roads, with their clocks
    get campaign_table_path(campaign)
    expect(response.body).to include("ticks The roads close")
  end

  it "shows the box a clock is about to fill by itself, to the GM and the table" do
    clock = campaign.clocks.create!(name: "The tide", segments: 4, triggers: %w[dawn], public: true)
    expect(clock.next_tick).to eq("new day")
    get campaign_prep_path(campaign)
    expect(response.body).to include("A dashed box fills by itself")
    expect(page.at("[data-change-key='clock-#{clock.id}'] i.is-next")).to be_present
    get campaign_table_path(campaign)
    expect(page.at("[data-change-key='clock-#{clock.id}'] i.is-next")).to be_present
  end

  it "arrives on a card: the travel line carries the cue and the place" do
    edge = campaign.current_node.edges.reject(&:blocked?).find { |e| e.state == "open" }
    campaign.travel!(edge)
    line = campaign.messages.where(cue: "arrival").last
    expect(line.data).to include("moved" => true, "place" => campaign.current_node.name, "kind" => campaign.current_node.kind.humanize)
    get campaign_table_path(campaign)
    expect(page.at("[data-moment-cue=arrival]")).to be_present
    # The line carries what the card shows, so the card isn't blank (moment_controller fills it from the line).
    card = page.at("##{ActionView::RecordIdentifier.dom_id(line)}")["data-chat-line-card-value"]
    expect(JSON.parse(card)).to include("place" => campaign.current_node.name, "kind" => campaign.current_node.kind.humanize)
  end

  it "marks the Now band's state and, on the stage's map, the party's marker, so a change wipes and hops" do
    get campaign_table_path(campaign)
    now = page.at("[data-change=state]")
    expect(now["data-state"]).to eq("free")
    expect(now["data-controls"]).to eq("talk")
    campaign.show_map!
    get campaign_table_path(campaign)
    marker = page.at(".map-party")
    expect(marker["transform"]).to be_present
    expect(marker["data-change"]).to eq("marker")
    expect(marker["data-change-key"]).to eq("party")
  end

  it "shows the vote filling: pickers as chips, each option's share as a bar" do
    choice = Message.choice(campaign, options: [ "Left", "Right" ]).tap(&:save!)
    choice.picks.create!(character: rook, option: "Left")
    get campaign_table_path(campaign)
    chip = page.at("i.choice__chip[data-change-key=Rook]")
    expect(chip.text).to eq("R")
    expect(chip["aria-hidden"]).to eq("true")
    expect(page.at("[data-change=bar]")["style"]).to eq("width: 100%")
    footer = page.at("p.choice__footer") # who has picked, as the vote's footer, changing as they do
    expect(footer["data-change"]).to eq("text")
    expect(footer.text.squish).to eq("Picked: Rook.")
  end
end
