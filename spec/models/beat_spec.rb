# frozen_string_literal: true

require "rails_helper"

RSpec.describe Beat do
  let(:campaign) { create_campaign }
  let!(:cid) { campaign.npcs.create!(name: "Cid", title: "Engineer") }
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let(:scene) { campaign.scenes.create!(name: "The airship falls", script: "Cid (worried): The airship won't hold.\nThe wind picks up.\nBartz: Hold on!") }

  it "is what a script's lines become, the party able to speak too, and the script box is empty again" do
    expect(scene.beats.map(&:line)).to eq([
      { "speaker" => cid, "expression" => "worried", "text" => "The airship won't hold." },
      { "speaker" => nil, "expression" => nil, "text" => "The wind picks up." },
      { "speaker" => bartz, "expression" => nil, "text" => "Hold on!" }
    ])
    expect(scene.reload.script).to be_nil
    scene.update!(script: "Narrator: Later.")
    expect(scene.beats.reload.map(&:position)).to eq([ 0, 1, 2, 3 ])
    expect(scene.beats.last.text).to eq("Later.")
  end

  it "keeps the stage set by the beat before it, until a beat sets it again" do
    node = campaign.map_nodes.create!(name: "Walse", x: 1, y: 1, location: campaign.locations.create!(location_template: campaign.world.location_templates.create!(name: "Hall", kind: "town"), seed: 3))
    a, b, c = scene.beats.to_a
    a.update!(backdrop: "place", map_node: node)
    c.update!(backdrop: "black")
    expect(b.effective_backdrop).to eq("kind" => "place", "node" => node)
    expect(c.effective_backdrop).to eq("kind" => "black")
    expect(b.panel_template).to eq(node.location.location_template)
    expect(b.art_layers.map { |l| l["role"] }).to eq(%w[World Type Subject Detail])
    expect(b.art_layers.last["prompt"]).to eq("The wind picks up.")
    expect(b.art_title).to eq("The airship falls, beat 2")
  end

  it "refuses a place off this map, a face that isn't an expression, and a beat with nothing in it" do
    other = create_campaign(world: campaign.world, name: "Other").map_nodes.create!(name: "Elsewhere", x: 1, y: 1)
    expect(scene.beats.new(backdrop: "place", map_node: other, text: "x")).not_to be_valid
    expect(scene.beats.new(backdrop: "place", text: "x")).not_to be_valid
    expect(scene.beats.new(expression: "smug", text: "x")).not_to be_valid
    expect(scene.beats.new(text: "")).not_to be_valid
    expect(scene.beats.new(text: "", backdrop: "black")).to be_valid # a stage change alone
    expect(scene.beats.new(kind: "choice", options: [ "Only" ])).not_to be_valid
  end

  describe "on the stage" do
    it "is stepped by the GM: each beat says its line through the box (the party's too), then the ending plays" do
      node = campaign.map_nodes.create!(name: "Walse Tower", x: 3, y: 3, visible: false)
      scene.update!(ending: "reveal", map_node: node)
      scene.beats.second.update!(cue: "door", music: "boss")

      scene.start!
      expect(campaign.reload.staged_scene).to eq(scene)
      expect(scene.cursor).to eq(0)
      expect(campaign.staged_beat).to eq(scene.beats.first)
      expect(campaign.messages.last).to have_attributes(body: "The airship won't hold.", speaker: cid, expression: "worried")
      expect(campaign.messages.last).to be_dialogue

      scene.advance!
      expect(campaign.messages.last).to have_attributes(body: "The wind picks up.", cue: "door")
      expect(campaign.reload.music).to eq("boss")

      scene.advance!
      expect(campaign.messages.last).to have_attributes(body: "Hold on!", speaker: bartz)
      expect(campaign.messages.last).to be_dialogue # the GM wrote it for them
      expect(scene).to be_last_beat

      expect(scene.advance!).to be_nil
      expect(node.reload).to be_visible
      expect(campaign.reload.staged_scene).to be_nil
      expect(scene.reload).to be_played.and have_attributes(cursor: nil)
      expect { scene.advance! }.to raise_error(Refusal, /isn't on the stage/)
    end

    it "plays on by itself at reading pace until a choice, and pauses for the GM" do
      scene.update!(script: "? Jump | Hold on -> airship")
      scene.start!
      expect { scene.play_on! }.to have_enqueued_job(SceneStepJob).with(scene, 0)
      expect(scene.beats.first.seconds).to eq(4.6)

      SceneStepJob.perform_now(scene, 0)
      expect(scene.reload.cursor).to eq(1)
      SceneStepJob.perform_now(scene, 0) # stale: the GM stepped already, or it already ran
      expect(scene.reload.cursor).to eq(1)

      scene.pause!
      SceneStepJob.perform_now(scene, 1)
      expect(scene.reload.cursor).to eq(1)

      scene.play_on!
      SceneStepJob.perform_now(scene, 1)
      SceneStepJob.perform_now(scene, 2)
      expect(scene.reload.cursor).to eq(3) # the choice
      expect(scene).not_to be_auto
      expect(campaign.open_choice.options).to eq([ "Jump", "Hold on" ])
    end

    it "can be taken down without its ending, and one scene replaces another" do
      other = campaign.scenes.create!(name: "Other", script: "Narrator: Elsewhere.")
      scene.start!
      other.start!
      expect(scene.reload.cursor).to be_nil
      expect(campaign.reload.staged_scene).to eq(other)
      other.stop!
      expect(campaign.reload.staged_scene).to be_nil
      expect(other.reload).not_to be_played
      expect { campaign.scenes.create!(name: "Empty", ending: "battle", encounter: { "goblin" => 1 }).start! }.to raise_error(Refusal, /no beats/)
    end

    it "plays whole, beat after beat, the way it used to" do
      scene.update!(ending: "battle", encounter: { "goblin" => 2 })
      battle = scene.play!
      expect(battle).to be_a(BattleRecord)
      expect(campaign.messages.chronological.map(&:body).first(3)).to eq([ "The airship won't hold.", "The wind picks up.", "Hold on!" ])
      expect(campaign.reload.staged_scene).to be_nil
    end
  end
end
