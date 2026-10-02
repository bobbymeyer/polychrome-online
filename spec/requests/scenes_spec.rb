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
    expect(response.body).to include("Ambush", "1 beat, then a battle")

    create_character(campaign, name: "Bartz")
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    get campaign_table_path(campaign)
    expect(response.body).to include("Ambush", scene_play_path(scene))

    # On the stage: its first beat is said, and the GM steps it to its ending.
    post scene_play_path(scene)
    expect(campaign.messages.pluck(:body)).to include("Behind you!")
    expect(campaign.reload.staged_scene).to eq(scene)
    get campaign_table_path(campaign)
    expect(response.body).to include("A scene is on the stage: Ambush.", "Finish, then the battle", 'class="table-scene is-scene"')

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
    expect(response.body).to include("Beats", "Add beats from a script", "Ready?", "The fog lifts.", "Panel for beat 1", "Bartz (party)")

    post scene_beats_path(scene), params: { after_id: first.id }
    inserted = scene.beats.reload[1]
    expect(response).to redirect_to(edit_scene_path(scene, beat: inserted.id, anchor: "beat_#{inserted.id}"))
    expect(scene.beats.map(&:position)).to eq([ 0, 1, 2 ])
    expect(second.reload.position).to eq(2)

    bartz = campaign.characters.find_by!(name: "Bartz")
    patch beat_path(inserted), params: { beat: { speaker: "Character:#{bartz.id}", expression: "determined", text: "Always.", backdrop: "black", cue: "key", music: "boss",
                                                 figures: { "Npc:#{cid.id}" => { type: "Npc", id: cid.id, side: "left", expression: "happy" } } } }
    expect(inserted.reload).to have_attributes(speaker: bartz, expression: "determined", text: "Always.", backdrop: "black", cue: "key", music: "boss")
    expect(inserted.figures).to eq([ { "type" => "Npc", "id" => cid.id, "side" => "left", "expression" => "happy" } ])
    expect(inserted.on_stage.map { |f| [ f["who"], f["side"], f["speaking"] ] }).to eq([ [ cid, "left", false ], [ bartz, "right", true ] ])

    get edit_scene_path(scene, beat: inserted.id)
    expect(response.body).to include("Beat 2 of 3, as the table will see it", "beat-stage--black", "is-speaking")

    post beat_move_path(inserted), params: { direction: "up" }
    expect(scene.beats.reload.map(&:text)).to eq([ "Always.", "Ready?", "The fog lifts." ])
    post beat_copy_path(inserted)
    expect(scene.beats.reload.map(&:text)).to eq([ "Always.", "Always.", "Ready?", "The fog lifts." ])
    delete beat_path(inserted)
    expect(scene.beats.reload.map { |b| [ b.position, b.text ] }).to eq([ [ 0, "Always." ], [ 1, "Ready?" ], [ 2, "The fog lifts." ] ])

    # A choice is written as its line.
    patch beat_path(scene.beats.last), params: { beat: { speaker: "", text: "? Fight | Flee -> quay", backdrop: "keep" } }
    expect(scene.beats.last.reload).to have_attributes(kind: "choice", options: %w[Fight Flee], flag_key: "quay")
    expect(scene.reload.summary).to eq("2 beats, then a choice: Fight / Flee")
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
