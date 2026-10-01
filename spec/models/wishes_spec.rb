# frozen_string_literal: true

require "rails_helper"

RSpec.describe Location::Wishes do
  let(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:town) { campaign.locations.create!(location_template: village, seed: 5) }
  let!(:hollin) { campaign.map_nodes.create!(name: "Hollin", kind: "town", x: 1, y: 1, visible: true, location: town) }
  let!(:barrow) { campaign.map_nodes.create!(name: "The Barrow", kind: "dungeon", x: 9, y: 9) }
  let(:remedy) { world.items.find_by!(slug: "remedy") }
  let(:folk) do
    [ { "key" => "npc-0", "name" => "Oskar", "title" => "Townsfolk", "wish" => "My father's fever won't break.", "wants" => "remedy" },
      { "key" => "npc-1", "name" => "Lenne", "title" => "Townsfolk", "wish" => "I'd give anything to see {dungeon} quiet again." },
      { "key" => "npc-2", "name" => "Dorn", "title" => "Townsfolk", "wish" => "I keep a lantern in the window." } ]
  end

  before do
    campaign.map_edges.create!(from_node: hollin, to_node: barrow)
    campaign.update!(current_node: hollin)
    allow_any_instance_of(Location).to receive(:townsfolk).and_return(folk)
  end

  def ways = campaign.ways_on.map { |way| way["label"] }

  it "offers bringing what someone wished for as a thing to do, while the bag holds it" do
    expect(ways).not_to include(a_string_starting_with("Bring"))
    campaign.add_item!(remedy, 2)
    expect(ways).to include("Bring Oskar a Remedy")
  end

  it "hands it over, once, and the town thinks better of the party" do
    create_character(campaign, name: "Bartz")
    campaign.add_item!(remedy, 2)
    campaign.make_move!(campaign.ways_on.find { |way| way["label"] == "Bring Oskar a Remedy" }["move"])

    expect(campaign.quantity_of(remedy)).to eq(1)
    expect(town.reload.met?("npc-0")).to be(true)
    expect(campaign.messages.pluck(:body)).to include(a_string_starting_with("The party gives Oskar a Remedy. “"))
    expect(campaign.deeds.where(deed: "favour").count).to eq(1)
    expect(town.reload.reputation).to eq(1)
    expect(ways).not_to include(a_string_starting_with("Bring Oskar"))
    expect { town.meet_wish!("npc-0") }.to raise_error(Refusal, /already has what they wished for/)
    expect { town.meet_wish!("npc-2") }.to raise_error(Refusal, /isn't asking for anything/)
  end

  it "lets whoever wished the dungeon cleared be the one who welcomes the party back" do
    campaign.update!(welcomes: { hollin.id.to_s => "The Barrow" })
    campaign.welcome_back!(hollin)
    expect(campaign.messages.pluck(:body)).to include(a_string_starting_with("Lenne meets the party: “You cleared The Barrow? I'd given up asking anyone."))
    expect(town.reload.met?("npc-1")).to be(true)
  end
end
