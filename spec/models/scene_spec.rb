# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scene do
  let(:campaign) { create_campaign }
  let!(:cid) { campaign.npcs.create!(name: "Cid", title: "Engineer") }

  def scene(**attrs)
    campaign.scenes.new({ name: "The airship falls", script: "" }.merge(attrs))
  end

  it "reads its script like a play: the cast by name, with expressions, and narration for the rest" do
    lines = scene(script: <<~SCRIPT).lines
      Cid (worried): The airship won't hold.

      The wind picks up.
      narrator: A shadow crosses the moon.
      The sign on the door reads, in a shaky hand: keep out.
    SCRIPT
    expect(lines.map { |l| [ l["speaker"], l["expression"], l["text"] ] }).to eq([
      [ cid, "worried", "The airship won't hold." ],
      [ nil, nil, "The wind picks up." ],
      [ nil, nil, "A shadow crosses the moon." ],
      [ nil, nil, "The sign on the door reads, in a shaky hand: keep out." ]
    ])
  end

  it "says who isn't in the cast, and which expressions there are" do
    bad = scene(script: "Gilgamesh: En garde!\nCid (smug): Heh.")
    expect(bad).not_to be_valid
    expect(bad.errors[:script].join).to include("Gilgamesh isn't in the cast", "“smug” isn't an expression")
  end

  it "needs something to play, and an ending that's complete" do
    expect(scene).not_to be_valid
    expect(scene(ending: "battle", encounter: { "dragon" => 1 })).not_to be_valid
    expect(scene(ending: "battle", encounter: { "goblin" => 2 })).to be_valid
    expect(scene(ending: "reveal")).not_to be_valid
    other = create_campaign(world: campaign.world, name: "Other").map_nodes.create!(name: "Elsewhere", x: 1, y: 1)
    expect(scene(ending: "reveal", map_node: other)).not_to be_valid
  end

  it "plays its lines to the table in order, as dialogue, and reveals a place" do
    node = campaign.map_nodes.create!(name: "Walse Tower", x: 3, y: 3, visible: false)
    s = scene(script: "Cid (worried): Hold on!\nThe ship lurches.", ending: "reveal", map_node: node).tap(&:save!)
    s.play!

    said = campaign.messages.chronological.last(3)
    expect(said.map(&:body)).to eq([ "Hold on!", "The ship lurches.", "Walse Tower appears on the map." ])
    expect(said.first).to have_attributes(speaker: cid, expression: "worried")
    expect(said.first(2)).to all(be_dialogue)
    expect(node.reload).to be_visible
    expect(s.reload).to be_played
  end

  it "ends in a battle for everyone standing" do
    create_character(campaign, name: "Bartz")
    s = scene(script: "Cid: Here they come!", ending: "battle", encounter: { "goblin" => 2 }).tap(&:save!)
    battle = s.play!
    expect(battle).to be_a(BattleRecord)
    expect(battle.name).to eq("The airship falls")
    expect(battle.enemies.size).to eq(2)
    expect(campaign.reload.pending_encounter).to be_nil
    expect(campaign.messages.chronological.map(&:body)).to start_with("Here they come!")
  end

  it "won't start a battle with nobody standing, and says nothing" do
    s = scene(script: "Cid: Here they come!", ending: "battle", encounter: { "goblin" => 2 }).tap(&:save!)
    expect { s.play! }.to raise_error(ArgumentError, /Nobody is standing/)
    expect(campaign.messages).to be_empty
  end
end
