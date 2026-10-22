# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Prep, in the order prep goes", type: :request do
  let!(:world) { base_world }
  let(:campaign) { base_campaign(name: "Pulp", gm: @admin) }

  before { sit(campaign, "gm") }

  def next_up
    page.css(".prep-next__list li a").map(&:text)
  end

  it "names the next few things to set up, and ticks them off as they are" do
    get campaign_prep_path(campaign)
    expect(next_up).to eq([ "Put the party somewhere", "Add someone to talk to", "Write a scene" ])
    expect(page.at(".prep-next a[href='#{campaign_maps_path(campaign)}']").text).to eq("Put the party somewhere")
    expect(page.at(".prep-next a[href='#{new_campaign_npc_path(campaign)}']").text).to eq("Add someone to talk to")
    expect(page.at(".prep-next .hint").text).to include("of 6 set up")

    campaign.update!(current_node: campaign.map_nodes.create!(name: "Tule", kind: "field", x: 1, y: 1, visible: true))
    get campaign_prep_path(campaign)
    expect(next_up.first).to eq("Add someone to talk to")
    expect(next_up).not_to include("Put the party somewhere")
    expect(page.at("#scenes")).to be_present # the anchors it points at are on the page
  end

  it "leaves the clutter of what the story has made so far after what is stocked, and says so" do
    get campaign_prep_path(campaign)
    expect(page.css(".prep-reference .drawers__tab").map(&:text)).to eq([ "Secrets", "Rumours", "Bag", "Deeds", "Flags" ])
    expect(page.css(".prep-reference .drawers__tabs > *").map(&:text)).to include("Running so far")
    expect(page.css(".prep-reference .drawers__tabs > *").map(&:text).index("Running so far")).to eq(3)
  end

  it "offers a way to make what a monster's form is missing, and pulls it in without a reload" do
    get new_world_bestiary_monster_path(world)
    missing = page.css("p.missing").map { |p| p.css("a").map { |a| [ a.text, a["href"] ] } }
    expect(missing).to contain_exactly(
      [ [ "New ability ↗", new_world_grimoire_ability_path(world) ] ],
      [ [ "New monster ↗", new_world_bestiary_monster_path(world) ] ],
      [ [ "New item ↗", new_world_armory_item_path(world) ] ]
    )
    expect(page.css("p.missing[data-controller=choices] button[data-action='choices#refresh']").size).to eq(3)
  end
end
