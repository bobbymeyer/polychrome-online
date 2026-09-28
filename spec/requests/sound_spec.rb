# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sound", type: :request do
  include ActiveJob::TestHelper

  let(:campaign) { create_campaign }
  let(:world) { campaign.world }

  # The smallest file that reads as audio: a WAV header and no samples.
  def wav(name = "field.wav")
    header = "RIFF" + [ 36 ].pack("V") + "WAVEfmt " + [ 16, 1, 1, 8000, 8000, 1, 8 ].pack("VvvVVvv") + "data" + [ 0 ].pack("V")
    Rack::Test::UploadedFile.new(StringIO.new(header), "audio/wav", original_filename: name)
  end

  def music_meta
    Nokogiri::HTML(response.body).at('meta[name="polychrome-music"]')
  end

  it "takes a world's tracks from its form, refuses what isn't audio, and removes them" do
    patch world_path(world), params: { world: { music_field: wav, music_battle: wav("battle.wav") } }
    expect(world.reload.music_track("field")).to be_present
    expect(world.music_track("battle").filename.to_s).to eq("battle.wav")
    expect(world.music_track("town")).to be_nil

    get edit_world_path(world)
    expect(response.body).to include("field.wav", "battle.wav", "Remove")

    png = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/goblin.png"), "image/png")
    patch world_path(world), params: { world: { music_town: png } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be an audio file")

    perform_enqueued_jobs { patch world_path(world), params: { world: { remove_music: [ "field" ] } } }
    expect(world.reload.music_track("field")).to be_nil
    expect(world.music_track("battle")).to be_present
  end

  it "has each game page ask for its scene's track, and a battle keep its own" do
    world.music_field.attach(wav)
    world.music_battle.attach(wav("battle.wav"))

    get campaign_table_path(campaign)
    expect(music_meta["content"]).to include("field.wav")
    expect(music_meta["data-fixed"]).to eq("false")

    campaign.update!(music: "battle")
    get campaign_path(campaign)
    expect(music_meta["content"]).to include("battle.wav")
    expect(music_meta["data-default"]).to include("field.wav")

    campaign.update!(music: "silence")
    get campaign_table_path(campaign)
    expect(music_meta["content"]).to eq("")

    get battle_path(start_battle(campaign: campaign))
    expect(music_meta["content"]).to include("battle.wav")
    expect(music_meta["data-fixed"]).to eq("true")
  end

  it "lets the GM switch the table's music, and every page hears about it" do
    create_character(campaign, name: "Bartz")
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    get campaign_table_path(campaign)
    expect(response.body).to include("Music for the table", "Follow the scene (field)", "Town (no track)")

    expect { patch campaign_music_path(campaign), params: { music: "dungeon" } }
      .to have_broadcasted_to(stream(campaign, :stage)).with(a_string_including('action="music"', 'follow="false"'))
    expect(campaign.reload.music).to eq("dungeon")

    patch campaign_music_path(campaign), params: { music: "nonsense" }
    expect(campaign.reload.music).to be_nil
  end

  it "doesn't let a player change the music" do
    campaign.update!(gm: make_user("GM"))
    sign_in_as(make_user("Player"))
    patch campaign_music_path(campaign), params: { music: "boss" }
    expect(campaign.reload.music).to be_nil
  end
end
