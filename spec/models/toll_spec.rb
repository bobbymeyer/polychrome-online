# frozen_string_literal: true

require "rails_helper"

RSpec.describe Toll do
  let(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let(:cave) { world.location_templates.find_by!(slug: "goblin_cave") }
  let(:dungeon) do
    campaign.locations.create!(location_template: cave, seed: 11).tap do |d|
      campaign.update!(current_node: campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 1, y: 1, location: d))
    end
  end
  let(:entrance) { dungeon.view["entrance"] }

  it "reads what a way takes from the brackets, as a thing to do's are read" do
    toll, problems = described_class.read("A sealed door. (pay 100, hurt 10, 2)")
    expect(problems).to be_empty
    expect(toll).to have_attributes(words: "A sealed door.", price: 100, takes: 2)
    expect(toll.outcomes.map(&:to_s)).to eq([ "hurt 10" ])
    expect(toll.describe(campaign)).to eq("100 gil, 10% of HP, 2 parts of the day")

    plain = described_class.of("A rope bridge: someone must stay behind.")
    expect(plain).to be_free
    expect(plain.words).to eq("A rope bridge: someone must stay behind.")
    expect(described_class.read("Mud. (swim 3)").last).to include(a_string_matching(/“swim 3” isn't a price/))
  end

  it "keeps fork rows to what the game can take" do
    forks = world.generator_tables.new(name: "Forks", kind: "forks", paste: "Gas. (hurt 10)\nMud. (swim 3) | 2")
    expect(forks).not_to be_valid
    expect(forks.entries).to eq([ { "text" => "Gas. (hurt 10)" }, { "text" => "Mud. (swim 3)", "weight" => 2 } ])
    expect(forks.errors[:entries]).to include(/row 2: “swim 3” isn't a price/)
  end

  describe "a costly way in a dungeon" do
    let!(:bartz) { create_character(campaign, name: "Bartz") }
    let(:gallery) do
      dungeon.enter!
      dungeon.add_room!(name: "Gallery", connect: entrance, decision: { "kind" => "event", "text" => "Dust." })
    end

    def cost_the_way(text)
      key = gallery
      allow(dungeon).to receive(:view).and_wrap_original do |original|
        original.call.tap { |v| v["paths"].find { |p| p["to"] == key }["cost"] = text }
      end
      key
    end

    it "is refused when the party can't pay, and taken once when it can" do
      key = cost_the_way("A sealed door. (pay 100)")
      campaign.update!(gil: 60)
      expect { dungeon.move_to!(key) }.to raise_error(Refusal, /has 60 gil; that way costs 100 gil/)
      expect(dungeon.reload.progress["current"]).to eq(entrance)

      campaign.update!(gil: 150)
      dungeon.move_to!(key)
      expect(campaign.reload.gil).to eq(50)
      expect(campaign.messages.pluck(:body)).to include("The cost of that way: A sealed door.", "The party pays 100 gil.")
      dungeon.move_to!(entrance)
      dungeon.move_to!(key)
      expect(campaign.reload.gil).to eq(50)
    end

    it "names its toll among the ways on until it's paid" do
      cost_the_way("Poison gas. (hurt 10)")
      expect(campaign.ways_on.map { |w| w["label"] }).to include(a_string_ending_with(" (costs 10% of HP)"))
    end

    it "takes a share of everyone's HP, never the last of it, and lets time pass" do
      key = cost_the_way("Thorns. (hurt 50, 1)")
      bartz.update!(hp: 3)
      faris = create_character(campaign, name: "Faris")
      expect { dungeon.move_to!(key) }.to change { campaign.reload.period }
      expect(bartz.reload.current_hp).to eq(1)
      expect(faris.reload.current_hp).to eq(faris.stats["max_hp"] - (faris.stats["max_hp"] / 2.0).ceil)
      expect(campaign.messages.pluck(:body)).to include(a_string_starting_with("It takes its toll: Bartz −2"))
    end

    it "can wake a fight from the place's table" do
      key = cost_the_way("Loose rock. (ambush)")
      dungeon.move_to!(key)
      expect(campaign.reload.pending_encounter).to include("table" => "#{dungeon.name}: on the way")
    end

    it "leaves a cost without brackets for the GM to play out" do
      key = cost_the_way("A rope bridge: someone must stay behind.")
      expect(campaign.ways_on.map { |w| w["label"] }).to include(a_string_ending_with("(costly)"))
      dungeon.move_to!(key)
      expect(campaign.messages.pluck(:body)).to include("The cost of that way: A rope bridge: someone must stay behind.")
      expect(campaign.ways_on.map { |w| w["label"] }).not_to include(a_string_ending_with("(costly)"))
    end
  end
end
