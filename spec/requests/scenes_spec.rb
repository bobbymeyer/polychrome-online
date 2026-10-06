# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Scenes", type: :request do
  let(:campaign) { create_campaign }
  let!(:cid) { campaign.npcs.create!(name: "Cid") }

  it "are written on the campaign page and played from the table" do
    get new_campaign_scene_path(campaign)
    expect(response.body).to include("The cast: Cid.")

    post campaign_scenes_path(campaign), params: { scene: {
      name: "Ambush", script: "Cid (angry): Behind you!", ending: "battle",
      encounter: { "0" => { monster: "goblin", count: "2" }, "1" => { monster: "goblin", count: "1" }, "2" => { monster: "", count: "1" } }
    } }
    scene = campaign.scenes.last
    expect(response).to redirect_to(edit_scene_path(scene))
    expect(scene.encounter).to eq("goblin" => 3)
    expect(scene.beats.map(&:line)).to eq([ { "speaker" => cid, "expression" => "angry", "text" => "Behind you!" } ])

    get campaign_prep_path(campaign)
    expect(response.body).to include("Ambush", "1 line, then a battle")

    create_character(campaign, name: "Bartz")
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    get campaign_table_path(campaign)
    expect(response.body).not_to include(scene_play_path(scene)) # until the GM calls Scene (Campaign::Controls)
    campaign.call_controls!("scene")
    get campaign_table_path(campaign)
    expect(response.body).to include("Ambush", scene_play_path(scene))

    # On the stage: its first beat is said, and the GM steps it to its ending.
    post scene_play_path(scene)
    expect(campaign.messages.pluck(:body)).to include("Behind you!")
    expect(campaign.reload.staged_scene).to eq(scene)
    get campaign_table_path(campaign)
    expect(response.body).not_to include("A scene is on the stage") # no title card: the stage is the scene
    corner = Nokogiri::HTML(response.body).at("#table_time .table-time__scene")
    expect(corner.text.squish).to include("1/1", "Finish, then the battle")
    expect(response.body).to include('class="table-scene is-scene"', 'data-state="scene"')

    patch scene_play_path(scene), params: { go: "next" }
    expect(campaign.battles.last.name).to eq("Ambush")
    expect(campaign.reload.staged_scene).to be_nil
    expect(scene.reload).to be_played
  end

  it "has a sequencer on its page: beats added, written, moved, doubled and deleted, with a preview of the one chosen" do
    create_character(campaign, name: "Bartz")
    scene = campaign.scenes.create!(name: "The quay", script: "Cid: Ready?\nNarrator: The fog lifts.")
    first, second = scene.beats.to_a

    get edit_scene_path(scene)
    expect(response.body).to include("Steps", "Add lines from a script", "Ready?", "The fog lifts.", "Panel for step 1", "Bartz (party)", "add-step__kind")

    # A line inserted after the first, written for one of the party.
    post scene_beats_path(scene), params: { kind: "say", after_id: first.id }
    inserted = scene.beats.reload[1]
    expect(response).to redirect_to(edit_scene_path(scene, beat: inserted.id, anchor: "beat_#{inserted.id}"))
    expect(scene.beats.map(&:position)).to eq([ 0, 1, 2 ])
    expect(second.reload.position).to eq(2)
    bartz = campaign.characters.find_by!(name: "Bartz")
    patch beat_path(inserted), params: { beat: { speaker: "Character:#{bartz.id}", expression: "determined", text: "Always.", cue: "key" } }
    expect(inserted.reload).to have_attributes(kind: "say", speaker: bartz, expression: "determined", text: "Always.", cue: "key")

    # The stage, step by step: a black backdrop first, Cid entering on the left, music, an effect.
    post scene_beats_path(scene), params: { kind: "backdrop" }
    backdrop = scene.beats.reload.last
    expect(backdrop).to have_attributes(kind: "backdrop", backdrop: "black")
    post beat_move_path(backdrop), params: { direction: "up" }
    post beat_move_path(backdrop), params: { direction: "up" }
    post beat_move_path(backdrop), params: { direction: "up" }
    post scene_beats_path(scene), params: { kind: "sprite", after_id: backdrop.id }
    sprite = scene.beats.reload[1]
    expect(sprite).to have_attributes(kind: "sprite", action: "enter")
    patch beat_path(sprite), params: { beat: { who: "Npc:#{cid.id}", action: "enter", side: "left", expression: "happy", transition: "slide" } }
    expect(sprite.reload).to have_attributes(figures: [ { "type" => "Npc", "id" => cid.id, "side" => "left", "expression" => "happy" } ], transition: "slide")
    post scene_beats_path(scene), params: { kind: "music", after_id: sprite.id }
    patch beat_path(scene.beats.reload[2]), params: { beat: { music: "boss" } }
    post scene_beats_path(scene), params: { kind: "fx", after_id: scene.beats.reload[2].id }
    patch beat_path(scene.beats.reload[3]), params: { beat: { fx: "shake" } }
    expect(scene.beats.reload.map(&:kind)).to eq(%w[backdrop sprite music fx say say say])
    expect(inserted.reload.on_stage.map { |f| [ f["who"], f["side"], f["speaking"] ] }).to eq([ [ cid, "left", false ], [ bartz, "right", true ] ])
    expect(inserted.effective_backdrop).to eq("kind" => "black")

    get edit_scene_path(scene, beat: inserted.id)
    expect(response.body).to include("Step 6 of 7", "Bartz: Always.", "beat-stage--black", "is-speaking", 'data-fx="shake"', "Effect on: shake")
    expect(response.body).not_to include("data-arrive=") # the changes played on the line before this one
    # The changes come on with the first line after them: Cid slides in, the black backdrop fades; the form says how.
    first_line = scene.beats.in_order[4]
    get edit_scene_path(scene, beat: first_line.id)
    expect(response.body).to include('data-arrive="slide"', %(data-arrive-key="#{first_line.id}:Npc:#{cid.id}"), 'data-arrive="fade"', "Comes on with", "Slide in")
    # Run through from here: the next step rides a frame load, playing on at reading pace until the choice.
    expect(response.body).to include("Play from here", 'data-scene-preview-playing-value="false"', 'data-scene-preview-stops-value="false"')
    get edit_scene_path(scene, beat: scene.beats.in_order[5].id, playing: 1)
    expect(response.body).to include("Pause", 'data-scene-preview-playing-value="true"', 'data-scene-preview-seconds-value="3.6"')

    post beat_copy_path(inserted)
    expect(scene.beats.reload.map(&:text).compact_blank).to eq([ "Ready?", "Always.", "Always.", "The fog lifts." ])
    delete beat_path(inserted)
    expect(scene.beats.reload.map(&:position)).to eq((0..6).to_a)

    # A choice is written as its line.
    patch beat_path(scene.beats.last), params: { beat: { speaker: "", text: "? Fight | Flee -> quay" } }
    get edit_scene_path(scene, beat: scene.beats.last.id)
    expect(response.body).to include("The table decides here: playing on stops.", "Play from the start", 'data-scene-preview-stops-value="true"')
    expect(scene.beats.last.reload).to have_attributes(kind: "choice", options: %w[Fight Flee], flag_key: "quay")
    expect(scene.reload.summary).to eq("2 lines, 4 changes, then a choice: Fight / Flee")
  end

  it "starts from a name alone, built step by step after" do
    post campaign_scenes_path(campaign), params: { scene: { name: "Blank", script: "", ending: "none" } }
    scene = campaign.scenes.last
    expect(response).to redirect_to(edit_scene_path(scene))
    expect(scene.beats).to be_empty
    expect(scene.summary).to eq("0 lines")
  end

  it "re-renders with what's wrong in the script" do
    post campaign_scenes_path(campaign), params: { scene: { name: "Oops", script: "Kefka: Hohoho!", ending: "none" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Kefka isn&#39;t in the cast")
  end

  it "are the GM's alone" do
    campaign.update!(gm: make_user("GM"))
    sign_in_as(make_user("Player"))
    scene = campaign.scenes.create!(name: "Secret", script: "Narrator: The twist.")
    post scene_play_path(scene)
    expect(campaign.messages).to be_empty
    get campaign_path(campaign)
    expect(response.body).not_to include("Secret", "Prep")
    get campaign_prep_path(campaign)
    expect(response).to redirect_to(root_path)
  end
end
