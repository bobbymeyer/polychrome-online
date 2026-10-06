# frozen_string_literal: true

# Makes one Track in ComfyUI with ACE-Step: submits it, then checks back
# every few seconds until the audio lands, it fails, or it times out
# (ApplicationJob#poll_comfy, as ArtBatchJob). ComfyUI out of reach is
# waited for; ComfyUI refusing (no checkpoint, a bad graph) fails the track
# with its reason.
class TrackJob < ApplicationJob
  discard_on ActiveJob::DeserializationError # the track was deleted
  waits_for_services do |job, error|
    job.arguments.first.fail!("#{error.message}. Tried for a day; make it again once it's back.")
  end

  def perform(track, client: Comfy.client)
    return unless track.generated?

    poll_comfy(track, client) { track.submit!(client) }
  end
end
