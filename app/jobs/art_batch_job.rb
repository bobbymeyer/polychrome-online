# frozen_string_literal: true

# Drives an ArtBatch (docs/HANDOFF.md §8): submits its candidates to ComfyUI,
# then checks back every few seconds and collects each image as it lands,
# until all are in, the batch fails, or it times out. It re-enqueues itself
# rather than sleeping, so it never holds a worker while ComfyUI renders.
#
# When ComfyUI can't be reached at all (it's asleep, restarting, off the
# network), nothing is lost: the batch waits and the job tries again, less
# often the longer it's been, for up to a day. ComfyUI answering with an
# error (a missing model, a bad graph) still fails the batch, with its reason.
class ArtBatchJob < ApplicationJob
  POLL = 3.seconds
  RETRY_FIRST = 30.seconds
  RETRY_MOST = 10.minutes
  GIVE_UP = 1.day

  discard_on ActiveJob::DeserializationError # the batch was discarded or replaced

  def perform(batch, client: Comfy.client, llm: Llm.enabled? ? Llm.client : nil, unreachable_since: nil)
    return if batch.finished?

    if batch.status.in?(%w[queued waiting])
      batch.write_prompt!(llm) if llm
      batch.upload_source!(client)
      batch.submit!(client)
    end
    return if batch.collect!(client)

    if batch.timed_out?
      batch.fail!("ComfyUI didn't finish within #{Comfy.config.fetch(:timeout, 900).to_i / 60} minutes")
    else
      self.class.set(wait: POLL).perform_later(batch)
    end
  rescue Comfy::Unreachable => e
    wait_for_comfy(batch, e.message, unreachable_since || Time.current)
  rescue Comfy::Error => e
    batch.fail!(e.message)
  end

  # How long until the next try: half the time it's been down so far,
  # within bounds (30 seconds, then a minute, two... up to ten).
  def self.retry_in(down_for)
    (down_for / 2).clamp(RETRY_FIRST, RETRY_MOST)
  end

  private

  def wait_for_comfy(batch, message, since)
    if since < GIVE_UP.ago
      batch.fail!("#{message}. Tried for a day; start it again once ComfyUI is back.")
    else
      batch.wait!(message)
      self.class.set(wait: self.class.retry_in(Time.current - since)).perform_later(batch, unreachable_since: since)
    end
  end
end
