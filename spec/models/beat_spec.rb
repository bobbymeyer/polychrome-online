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

  it "folds the stage from the steps before: the backdrop set, who entered, changed and left, the effect" do
    node = campaign.map_nodes.create!(name: "Walse", x: 1, y: 1, location: campaign.locations.create!(location_template: campaign.world.location_templates.create!(name: "Hall", kind: "town"), seed: 3))
    a, b, c = scene.beats.to_a
    place = scene.beats.create!(kind: "backdrop", backdrop: "place", map_node: node, position: 0)
    enter = scene.beats.create!(kind: "sprite", action: "enter", figures: [ { type: "Npc", id: cid.id, side: "right", expression: "happy" } ], position: 0)
    scene.beats.reload.each { |s| s.update_columns(position: [ enter, place, a, b, c ].index(s)) }
    expect(a.reload.effective_backdrop).to eq("kind" => "place", "node" => node)
    expect(a.on_stage.map { |f| [ f["who"], f["side"], f["expression"], f["speaking"] ] }).to eq([ [ cid, "right", "worried", true ] ]) # placed, and speaking with the line's face

    black = scene.beats.create!(kind: "backdrop", backdrop: "black", position: 5)
    leave = scene.beats.create!(kind: "sprite", action: "leave", figures: [ { type: "Npc", id: cid.id } ], position: 6)
    fx = scene.beats.create!(kind: "fx", fx: "shake", position: 7)
    last = scene.beats.create!(text: "Gone.", position: 8)
    expect(scene.reload.stage_at(black)["figures"].map { |f| f["who"] }).to eq([ cid ])
    expect(scene.stage_at(leave)["figures"]).to eq([])
    expect(last.effective_backdrop).to eq("kind" => "black")
    expect(last.effect).to eq("shake")
    expect(last.on_stage).to eq([]) # narration: nobody

    panel = scene.beats.create!(kind: "backdrop", backdrop: "panel", position: 3)
    scene.beats.reload.each { |s| s.update_columns(position: [ enter, place, a, panel, b, c, black, leave, fx, last ].index(s)) }
    expect(panel.panel_template).to eq(node.location.location_template) # the place set before it is the subject
    expect(panel.art_layers.map { |l| l["role"] }).to eq(%w[World Type Subject Detail])
    expect(panel.art_layers.last["prompt"]).to eq("The airship won't hold.") # the line before it, until words are given
    expect(panel.art_title).to eq("The airship falls, step 4")
    expect(scene.summary).to eq("4 lines, 6 changes")
  end

  it "refuses a step that isn't whole of its kind" do
    other = create_campaign(world: campaign.world, name: "Other").map_nodes.create!(name: "Elsewhere", x: 1, y: 1)
    expect(scene.beats.new(kind: "backdrop", backdrop: "place", map_node: other)).not_to be_valid
    expect(scene.beats.new(kind: "backdrop", backdrop: "place")).not_to be_valid
    expect(scene.beats.new(kind: "backdrop", backdrop: "black")).to be_valid
    expect(scene.beats.new(expression: "smug", text: "x")).not_to be_valid
    expect(scene.beats.new(text: "")).not_to be_valid
    expect(scene.beats.new(kind: "choice", options: [ "Only" ])).not_to be_valid
    expect(scene.beats.new(kind: "sprite", action: "enter")).not_to be_valid # nobody
    expect(scene.beats.new(kind: "sprite", action: "wave", figures: [ { type: "Npc", id: cid.id } ])).not_to be_valid
    expect(scene.beats.new(kind: "sprite", action: "leave", figures: [ { type: "Npc", id: cid.id } ])).to be_valid
    expect(scene.beats.new(kind: "music", music: "polka")).not_to be_valid
    expect(scene.beats.new(kind: "music", music: "follow")).to be_valid
    expect(scene.beats.new(kind: "fx")).not_to be_valid
    expect(scene.beats.new(kind: "fx", fx: "fade")).to be_valid
  end

  describe "on the stage" do
    it "is stepped by the GM line to line, the changes between made on the way, then the ending plays" do
      node = campaign.map_nodes.create!(name: "Walse Tower", x: 3, y: 3, visible: false)
      scene.update!(ending: "reveal", map_node: node)
      scene.beats.second.update!(cue: "door")
      # A backdrop before the first line, and music before the second: made on the way to each line.
      a, b, c = scene.beats.to_a
      black = scene.beats.create!(kind: "backdrop", backdrop: "black")
      music = scene.beats.create!(kind: "music", music: "boss")
      scene.beats.reload.each { |s| s.update_columns(position: [ black, a, music, b, c ].index(s)) }
      scene.reload
      expect(scene.beats.reload.map(&:kind)).to eq(%w[backdrop say music say say])

      scene.start!
      expect(campaign.reload.staged_scene).to eq(scene)
      expect(scene.cursor).to eq(1) # past the backdrop, on the first line
      expect(campaign.staged_beat).to eq(scene.beats.second)
      expect(campaign.staged_beat.effective_backdrop).to eq("kind" => "black")
      expect(campaign.messages.last).to have_attributes(body: "The airship won't hold.", speaker: cid, expression: "worried")
      expect(campaign.messages.last).to be_dialogue
      expect(campaign.music).to be_nil

      scene.advance!
      expect(scene.cursor).to eq(3) # past the music
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
      expect { campaign.scenes.create!(name: "Empty", ending: "battle", encounter: { "goblin" => 1 }).start! }.to raise_error(Refusal, /no steps/)
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
