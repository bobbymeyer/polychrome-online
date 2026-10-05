# frozen_string_literal: true

# Makes one Track in ComfyUI with ACE-Step: submits it, then checks back
# every few seconds until the audio lands, it fails, or it times out,
# re-enqueueing itself rather than sleeping (like ArtBatchJob). ComfyUI out
# of reach is waited for; ComfyUI refusing (no checkpoint, a bad graph)
# fails the track with its reason.
class TrackJob < ApplicationJob
  POLL = 3.seconds

  discard_on ActiveJob::DeserializationError # the track was deleted
  waits_for_services do |job, error|
    job.arguments.first.fail!("#{error.message}. Tried for a day; make it again once it's back.")
  end

  def perform(track, client: Comfy.client)
    return if track.finished? || !track.generated?

    track.submit!(client) if track.status.in?(%w[queued waiting])
    return if track.collect!(client)

    if track.timed_out?
      track.fail!("ComfyUI didn't finish within #{Comfy.config.fetch(:timeout, 900).to_i / 60} minutes")
    else
      self.class.set(wait: POLL).perform_later(track)
    end
  rescue Remote::Unreachable => e
    track.wait!(e.message)
    raise
  rescue Comfy::Error => e
    track.fail!(e.message)
  end
end
