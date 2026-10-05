# frozen_string_literal: true

# One piece of music in a world's Music book. A track is for a kind of
# scene (field, town, dungeon, battle, boss: the one the table plays there)
# or for nothing in particular, for the GM to call by name from the stage.
# It comes from one of three places: a file uploaded, a YouTube or Spotify
# link (played in their own small player, since those can't be fetched), or
# ACE-Step in ComfyUI, made from a description and lyrics (TrackJob).
class Track < ApplicationRecord
  SOURCES = %w[upload link generated].freeze
  SOURCE_LABELS = { "upload" => "Uploaded", "link" => "Linked", "generated" => "Generated" }.freeze
  # A generated track's way through ComfyUI; waiting: it couldn't be reached, TrackJob tries again.
  STATUSES = %w[queued waiting running done failed].freeze
  MAX_BYTES = World::MUSIC_MAX_BYTES
  SECONDS = (10..240)

  # The links that play: a YouTube video, or a Spotify track, album, playlist or episode.
  YOUTUBE = %r{\A(?:https?://)?(?:www\.|m\.|music\.)?(?:youtube\.com/(?:watch\?(?:.*&)?v=|shorts/|embed/|live/)|youtu\.be/)([\w-]{11})}
  SPOTIFY = %r{\A(?:https?://)?open\.spotify\.com/(?:intl-[a-z]{2}/)?(track|album|playlist|episode)/([A-Za-z0-9]+)}

  belongs_to :world
  has_one_attached :audio

  normalizes :name, :url, :prompt, :lyrics, with: ->(value) { value.to_s.strip.presence }
  normalizes :scene, with: ->(value) { value.presence }

  validates :name, presence: true
  validates :scene, inclusion: { in: World::MUSIC }, allow_nil: true
  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }, allow_nil: true
  validates :seconds, inclusion: { in: SECONDS }
  validates :url, presence: true, if: :link?
  validates :prompt, presence: true, if: :generated?
  validate :link_plays, if: :link?
  validate :audio_is_audio

  scope :in_order, -> { order(:position, :id) }

  after_commit :refresh_watchers
  after_commit -> { world.campaigns.find_each(&:broadcast_music) }, on: :update, if: -> { saved_change_to_scene? || saved_change_to_url? || saved_change_to_status? }

  def upload? = source == "upload"
  def link? = source == "link"
  def generated? = source == "generated"

  # Whether there is anything to hear yet.
  def playable? = link? ? embed_url.present? : audio.attached?

  # What the page plays (sound.js): a file's path, or the link's player.
  def play_url
    return embed_url if link?

    Rails.application.routes.url_helpers.rails_blob_path(audio, only_path: true) if audio.attached?
  end

  # YouTube and Spotify play in their own small player: an embed of the link,
  # on repeat where the player allows it.
  def embed_url
    return unless link? && url

    if (m = url.match(YOUTUBE))
      "https://www.youtube-nocookie.com/embed/#{m[1]}?autoplay=1&loop=1&playlist=#{m[1]}&rel=0"
    elsif (m = url.match(SPOTIFY))
      "https://open.spotify.com/embed/#{m[1]}/#{m[2]}"
    end
  end

  def service
    return "YouTube" if url&.match?(YOUTUBE)

    "Spotify" if url&.match?(SPOTIFY)
  end

  # The link as the service writes it, from what was pasted: safe to put in a page.
  def link_href
    return unless link? && url

    if (m = url.match(YOUTUBE))
      "https://www.youtube.com/watch?v=#{m[1]}"
    elsif (m = url.match(SPOTIFY))
      "https://open.spotify.com/#{m[1]}/#{m[2]}"
    end
  end

  # Where it stands, in a word, for the book's list.
  def state
    return "ComfyUI: #{status}" if generated? && status.present? && status != "done"

    playable? ? SOURCE_LABELS[source] : "No file yet"
  end

  # --- ACE-Step in ComfyUI (TrackJob) ----------------------------------------

  def generate!
    raise Refusal, "Only a generated track is made in ComfyUI" unless generated?

    update!(status: "queued", error: nil, prompt_id: nil, started_at: nil)
    TrackJob.perform_later(self)
  end

  def finished? = status.in?(%w[done failed])

  def submit!(client)
    graph = Comfy::Music.build(self, seed: Random.rand(2**31), capabilities: client.capabilities)
    update!(prompt_id: client.submit(graph), status: "running", started_at: Time.current, error: nil)
  end

  # True once the audio is in; false while ComfyUI is still at it.
  def collect!(client)
    files = client.result(prompt_id)
    return false if files.nil?

    file = files.first or raise Comfy::Error, "ComfyUI saved no audio"
    extension = File.extname(file["filename"].to_s).delete(".").presence || "flac"
    audio.attach(io: StringIO.new(client.fetch(file)), filename: "#{name.parameterize}.#{extension}",
                 content_type: Marcel::MimeType.for(extension: extension), identify: false) # ComfyUI's file is what its name says
    update!(status: "done")
    true
  end

  def timed_out? = started_at.present? && started_at < Comfy.config.fetch(:timeout, 900).to_i.seconds.ago

  def fail!(message) = update!(status: "failed", error: message.to_s.truncate(500))
  def wait!(message) = update!(status: "waiting", error: message.to_s.truncate(500))

  private

  def link_plays
    errors.add(:url, "must be a YouTube or Spotify link") if url && embed_url.nil?
  end

  def audio_is_audio
    return unless audio.attached?

    errors.add(:audio, "must be an audio file") unless audio.blob.content_type.to_s.start_with?("audio/")
    errors.add(:audio, "must be under #{MAX_BYTES / 1.megabyte} MB") if audio.blob.byte_size > MAX_BYTES
  end

  # The book's page, open while a track is being made, follows along.
  def refresh_watchers
    Turbo::StreamsChannel.broadcast_action_to(world, :music, action: :reload_frame, target: "music_book")
  end
end
