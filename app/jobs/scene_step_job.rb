# frozen_string_literal: true

# A scene playing on by itself (Scene#play_on!): the next beat, once the
# last has been read, as long as the GM hasn't stepped in or paused it.
class SceneStepJob < ApplicationJob
  discard_on ActiveJob::DeserializationError # the scene is gone

  def perform(scene, cursor)
    return unless scene.staged? && scene.auto? && scene.cursor == cursor

    scene.advance!
    scene.schedule_step! if scene.reload.staged? && scene.auto?
  rescue Refusal
    scene.pause!
  end
end
