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

  def music_meta = page.at('meta[name="polychrome-music"]')

  def track(scene, name = scene.capitalize, file: wav("#{scene}.wav"))
    world.tracks.create!(name: name, scene: scene).tap { |t| t.audio.attach(file) }
  end

  it "takes a world's tracks in its Music book: uploaded, linked, or refused when they're neither" do
    get world_tracks_path(world)
    expect(response.body).to include("No music yet")

    post world_tracks_path(world), params: { track: { name: "Fields", scene: "field", source: "upload", audio: wav } }
    expect(world.reload.music_track("field")).to have_attributes(name: "Fields")
    expect(world.music_track("field").audio.filename.to_s).to eq("field.wav")
    expect(world.music_track("town")).to be_nil

    png = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/goblin.png"), "image/png")
    post world_tracks_path(world), params: { track: { name: "Town", scene: "town", source: "upload", audio: png } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be an audio file")

    post world_tracks_path(world), params: { track: { name: "Tavern night", source: "link", url: "https://youtu.be/dQw4w9WgXcQ?t=3" } }
    tavern = world.tracks.find_by!(name: "Tavern night")
    expect(tavern.embed_url).to eq("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?autoplay=1&loop=1&playlist=dQw4w9WgXcQ&rel=0")
    post world_tracks_path(world), params: { track: { name: "Boss", scene: "boss", source: "link", url: "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC" } }
    expect(world.reload.music_track("boss").embed_url).to eq("https://open.spotify.com/embed/track/4uLU6hMCjMI75M1A2tKUQC")
    post world_tracks_path(world), params: { track: { name: "Nope", source: "link", url: "https://example.com/song.mp3" } }
    expect(response.body).to include("must be a YouTube or Spotify link")

    get world_tracks_path(world)
    expect(response.body).to include("Fields", "field.wav", "YouTube", "Spotify", "In the field", "When called")

    delete world_track_path(world, tavern)
    expect(world.tracks.exists?(tavern.id)).to be(false)
  end

  it "only takes music that is uploaded or linked: it makes none" do
    post world_tracks_path(world), params: { track: { name: "The long road", source: "generated" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(world.tracks).to be_empty

    get new_world_track_path(world)
    expect(response.body).to include("A file", "YouTube or Spotify")
    expect(response.body).not_to include("ComfyUI")
  end

  it "has each game page ask for its scene's track, and a battle keep its own" do
    track("field")
    track("battle")

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

  it "lets the GM switch the table's music from the stage, by scene or by name, and every page hears about it" do
    create_character(campaign, name: "Bartz")
    named = world.tracks.create!(name: "Tavern night", source: "link", url: "https://youtu.be/dQw4w9WgXcQ")
    at_the_table(campaign, as: "gm")
    stage = page.at("#stage #stage_music")
    expect(stage.text).to include("Music for the table", "Follow the scene (field)", "Town (no track)", "♪ Tavern night")

    expect { patch campaign_music_path(campaign), params: { music: "dungeon" } }
      .to have_broadcasted_to(stream(campaign, :stage)).with(a_string_including('action="music"', 'follow="false"'))
    expect(campaign.reload.music).to eq("dungeon")

    # A track by name: the page is told where its player is.
    expect { patch campaign_music_path(campaign), params: { music: "track:#{named.id}" } }
      .to have_broadcasted_to(stream(campaign, :stage)).with(a_string_including("youtube-nocookie.com/embed/dQw4w9WgXcQ"))
    expect(campaign.reload.music).to eq("track:#{named.id}")
    get campaign_table_path(campaign)
    expect(music_meta["content"]).to include("youtube-nocookie.com/embed/dQw4w9WgXcQ")
    patch campaign_music_path(campaign), params: { music: "track:999999" }
    expect(campaign.reload.music).to be_nil # not one of the world's: back to following the scene

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
