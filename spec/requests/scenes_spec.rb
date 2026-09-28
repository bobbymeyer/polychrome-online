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
    expect(response).to redirect_to(campaign_path(campaign, anchor: "scenes"))
    expect(scene.encounter).to eq("goblin" => 3)

    get campaign_path(campaign)
    expect(response.body).to include("Ambush", "1 line, then a battle")

    create_character(campaign, name: "Bartz")
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    get campaign_table_path(campaign)
    expect(response.body).to include("Ambush", scene_play_path(scene))

    post scene_play_path(scene)
    expect(campaign.messages.pluck(:body)).to include("Behind you!")
    expect(campaign.battles.last.name).to eq("Ambush")
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
    expect(response.body).not_to include("Secret")
  end
end
