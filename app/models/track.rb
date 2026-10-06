# frozen_string_literal: true

# One piece of music in a world's Music book. A track is for a kind of
# scene (field, town, dungeon, battle, boss: the one the table plays there)
# or for nothing in particular, for the GM to call by name from the stage.
# It comes from one of two places: a file uploaded, or a YouTube or Spotify
# link (played in their own small player, since those can't be fetched).
class Track < ApplicationRecord
  SOURCES = %w[upload link].freeze
  SOURCE_LABELS = { "upload" => "Uploaded", "link" => "Linked" }.freeze
  MAX_BYTES = World::MUSIC_MAX_BYTES

  # The links that play: a YouTube video, or a Spotify track, album, playlist or episode.
  YOUTUBE = %r{\A(?:https?://)?(?:www\.|m\.|music\.)?(?:youtube\.com/(?:watch\?(?:.*&)?v=|shorts/|embed/|live/)|youtu\.be/)([\w-]{11})}
  SPOTIFY = %r{\A(?:https?://)?open\.spotify\.com/(?:intl-[a-z]{2}/)?(track|album|playlist|episode)/([A-Za-z0-9]+)}

  belongs_to :world
  has_one_attached :audio

  normalizes :name, :url, with: ->(value) { value.to_s.strip.presence }
  normalizes :scene, with: ->(value) { value.presence }

  validates :name, presence: true
  validates :scene, inclusion: { in: World::MUSIC }, allow_nil: true
  validates :source, inclusion: { in: SOURCES }
  validates :url, presence: true, if: :link?
  validate :link_plays, if: :link?
  validate :audio_is_audio

  scope :in_order, -> { order(:position, :id) }

  after_commit -> { world.campaigns.find_each(&:broadcast_music) }, on: :update, if: -> { saved_change_to_scene? || saved_change_to_url? }

  def upload? = source == "upload"
  def link? = source == "link"

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
    return unless link?

    case parsed_link
    in [ "YouTube", _, id ] then "https://www.youtube-nocookie.com/embed/#{id}?autoplay=1&loop=1&playlist=#{id}&rel=0"
    in [ "Spotify", kind, id ] then "https://open.spotify.com/embed/#{kind}/#{id}"
    in nil then nil
    end
  end

  def service = parsed_link&.first

  # The link as the service writes it, from what was pasted: safe to put in a page.
  def link_href
    return unless link?

    case parsed_link
    in [ "YouTube", _, id ] then "https://www.youtube.com/watch?v=#{id}"
    in [ "Spotify", kind, id ] then "https://open.spotify.com/#{kind}/#{id}"
    in nil then nil
    end
  end

  # Where it stands, in a word, for the book's list.
  def state
    playable? ? SOURCE_LABELS[source] : "No file yet"
  end

  private

  # The pasted link read: [service, kind, id] ("YouTube", "video", the video's id; "Spotify", "track" /
  # "album" / "playlist" / "episode", its id), or nil for a link neither plays.
  def parsed_link
    return unless url

    if (m = url.match(YOUTUBE))
      [ "YouTube", "video", m[1] ]
    elsif (m = url.match(SPOTIFY))
      [ "Spotify", m[1], m[2] ]
    end
  end

  def link_plays
    errors.add(:url, "must be a YouTube or Spotify link") if url && embed_url.nil?
  end

  def audio_is_audio
    return unless audio.attached?

    errors.add(:audio, "must be an audio file") unless audio.blob.content_type.to_s.start_with?("audio/")
    errors.add(:audio, "must be under #{MAX_BYTES / 1.megabyte} MB") if audio.blob.byte_size > MAX_BYTES
  end
end
