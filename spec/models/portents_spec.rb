# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dangers: what a clock wants, its steps and their signs" do
  let(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:crossing) { campaign.map_nodes.create!(name: "Crossing", kind: "field", x: 1, y: 1, visible: true) }
  let(:hollin) do
    campaign.map_nodes.create!(name: "Hollin", kind: "town", x: 5, y: 5, visible: true, location: campaign.locations.create!(location_template: village, seed: 3))
  end
  let!(:rook) { create_character(campaign, name: "Rook") }
  let(:steps) do
    <<~STEPS
      The dockhands stop talking to strangers.
      - Fresh brass paint on every warehouse door.
      - A dockhand at {place} spits as they pass. | town
      Ships start mooring elsewhere.
      - Empty berths at {place}. | town
      The Syndicate buys the harbourmaster.
    STEPS
  end
  let(:clock) { campaign.clocks.create!(name: "The Syndicate takes the docks", segments: 4, impulse: "To own every berth", portents: steps) }

  def signs = campaign.messages.where(scope: "gm").pluck(:body).grep(/\AA sign of/)

  before do
    world.generator_tables.where(kind: "arrivals").destroy_all
    campaign.update!(current_node: crossing)
  end

  it "reads steps and their signs, and says what it can't read" do
    portents, problems = Portent.parse(steps)
    expect(portents.map(&:text)).to eq([ "The dockhands stop talking to strangers.", "Ships start mooring elsewhere.", "The Syndicate buys the harbourmaster." ])
    expect(portents.first.signs).to eq([ { "text" => "Fresh brass paint on every warehouse door." },
                                         { "text" => "A dockhand at {place} spits as they pass.", "when" => "town" } ])
    expect(problems).to be_empty
    expect(Portent.parse("- a sign first\nA step\n- bad | hurt >= lots").last)
      .to contain_exactly(a_string_starting_with("“- a sign first” is a sign"), a_string_including("isn't something a row can ask"))
    expect(campaign.clocks.new(name: "x", portents: "- orphan").valid?).to be(false)
  end

  it "tells the GM each step as its segment fills, and only the GM" do
    expect(clock.next_portent.text).to eq("The dockhands stop talking to strangers.")
    clock.tick!(2)
    expect(campaign.messages.where(scope: "gm").pluck(:body)).to eq([ "The Syndicate takes the docks, 1 of 4: The dockhands stop talking to strangers.",
                                                                      "The Syndicate takes the docks, 2 of 4: Ships start mooring elsewhere." ])
    expect(clock.next_portent.text).to eq("The Syndicate buys the harbourmaster.")
    clock.tick!(-1)
    expect(campaign.messages.where(scope: "gm").count).to eq(2)
  end

  it "offers a sign of the latest step it has reached when the party arrives, more often the fuller it is" do
    road = campaign.map_edges.create!(from_node: crossing, to_node: hollin)
    campaign.travel!(road)
    expect(signs).to be_empty # nothing reached yet

    clock.update!(filled: 4 - 1) # three quarters of the time
    offered = 12.times.count do
      campaign.place_party!(crossing)
      before = signs.size
      campaign.place_party!(hollin)
      signs.size > before
    end
    expect(offered).to be_between(4, 12)
    expect(signs.last).to eq("A sign of “The Syndicate takes the docks” (3 of 4): “Empty berths at Hollin.”")

    clock.update!(stopped_at: Time.current)
    expect { 4.times { campaign.place_party!(crossing); campaign.place_party!(hollin) } }.not_to(change { signs.size })
  end

  it "falls back to an earlier step's signs when the latest's don't fit" do
    clock.update!(filled: 2) # the latest step's only sign is for a town
    ford = campaign.map_nodes.create!(name: "Ford", kind: "field", x: 9, y: 9, visible: true)
    10.times { campaign.place_party!(ford); campaign.place_party!(crossing) }
    expect(signs).not_to be_empty
    expect(signs).to all(end_with("“Fresh brass paint on every warehouse door.”"))
  end

  it "is written on a front's clock in the setting and comes with it into a campaign" do
    front = world.world_fronts.create!(name: "The docks", clocks: [ { "name" => "The Syndicate moves", "segments" => 4, "impulse" => "To own the river", "portents" => steps } ])
    fresh = world.campaigns.create!(name: "Fresh")
    front.deal!(fresh)
    dealt = fresh.clocks.find_by!(name: "The Syndicate moves")
    expect(dealt).to have_attributes(impulse: "To own the river", portents: steps.strip)
    expect(world.world_fronts.find_by!(name: "The Barrow Lord's silver").clocks.map(&:impulse)).to all(be_present)
  end
end
