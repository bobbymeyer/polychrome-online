# frozen_string_literal: true

# The world's Music book (Track): a track for each kind of scene, and any
# number more for the GM to call by name. Every page at the table asks for
# one (ApplicationHelper#music_meta); a scene with no track is silent. The
# jingles are synthesised (sound.js), so they need nothing uploaded.
module World::Music
  extend ActiveSupport::Concern

  MUSIC = %w[field town dungeon battle boss].freeze
  MUSIC_MAX_BYTES = 25.megabytes

  included do
    has_many :tracks, -> { order(:position, :id) }, dependent: :destroy
  end

  # The track a kind of scene plays: the first in the book for it that has
  # anything to hear.
  def music_track(scene)
    return unless MUSIC.include?(scene.to_s)

    tracks.find { |track| track.scene == scene.to_s && track.playable? }
  end

  # Where a choice of music is heard from, or nil for silence: a kind of
  # scene, or one track by name ("track:12", Campaign#music).
  def music_path(choice)
    return if choice.blank? || choice.to_s == "silence"

    (named_track(choice) || music_track(choice))&.play_url
  end

  # The tracks the GM calls by name (not a kind of scene's), as choices for a
  # select: the stage's switch and a scene's music step.
  def named_music_choices
    tracks.select { |track| track.scene.nil? && track.playable? }.map { |track| [ "♪ #{track.name}", "track:#{track.id}" ] }
  end

  # The track a choice of music names ("track:12"), or nil: not that form, or
  # not one of this world's.
  def named_track(choice)
    id = choice.to_s.delete_prefix("track:")
    return if id == choice.to_s

    tracks.find { |track| track.id == id.to_i }
  end

  # Whether a choice of music names one of this world's tracks ("track:12").
  def music_track_choice?(choice) = named_track(choice).present?

  # Whether a choice of music is one the table can play: a kind of scene or
  # silence (Campaign::MUSIC_CHOICES), one of the extras the caller allows
  # ("follow" in a scene's music step), or one of this world's tracks by name.
  def music_choice?(choice, extra: [])
    Campaign::MUSIC_CHOICES.include?(choice) || extra.include?(choice) || music_track_choice?(choice)
  end

  def copy_music_from!(source)
    source.tracks.each do |track|
      copy = tracks.create!(track.attributes.except("id", "world_id", "created_at", "updated_at", "prompt_id", "started_at"))
      copy.audio.attach(track.audio.blob) if track.audio.attached?
    end
  end
end
