# frozen_string_literal: true

# Music for each kind of scene, uploaded by the world's author. Every page
# at the table asks for one (ApplicationHelper#music_meta); a scene with no
# track is silent. The jingles are synthesised (sound.js), so they need
# nothing uploaded.
module World::Music
  extend ActiveSupport::Concern

  MUSIC = %w[field town dungeon battle boss].freeze
  MUSIC_MAX_BYTES = 25.megabytes

  included do
    MUSIC.each { |scene| has_one_attached :"music_#{scene}" }
    validate :music_is_audio
  end

  def music_track(scene)
    return unless MUSIC.include?(scene.to_s)

    track = public_send(:"music_#{scene}")
    track if track.attached?
  end

  # Where a scene's track is served from, or nil for silence.
  def music_path(scene)
    track = music_track(scene)
    Rails.application.routes.url_helpers.rails_blob_path(track, only_path: true) if track
  end

  def copy_music_from!(source)
    MUSIC.each { |scene| (track = source.music_track(scene)) && public_send(:"music_#{scene}").attach(track.blob) }
  end

  private

  def music_is_audio
    MUSIC.each do |scene|
      track = public_send(:"music_#{scene}")
      next unless track.attached?

      errors.add(:"music_#{scene}", "must be an audio file") unless track.blob.content_type.to_s.start_with?("audio/")
      errors.add(:"music_#{scene}", "must be under #{MUSIC_MAX_BYTES / 1.megabyte} MB") if track.blob.byte_size > MUSIC_MAX_BYTES
    end
  end
end
