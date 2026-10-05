# frozen_string_literal: true

# Drives an ArtBatch (docs/HANDOFF.md §8): submits its candidates to ComfyUI,
# then checks back every few seconds and collects each image as it lands,
# until all are in, the batch fails, or it times out. It re-enqueues itself
# rather than sleeping, so it never holds a worker while ComfyUI renders.
#
# When ComfyUI or the language model can't be reached at all (asleep,
# restarting, off the network), nothing is lost: the batch says it's
# waiting, and the job is tried again (ApplicationJob.waits_for_services).
# ComfyUI answering with an error (a missing model, a bad graph) still fails
# the batch, with its reason.
class ArtBatchJob < ApplicationJob
  POLL = 3.seconds

  discard_on ActiveJob::DeserializationError # the batch was discarded or replaced
  waits_for_services do |job, error|
    job.arguments.first.fail!("#{error.message}. Tried for a day; start it again once it's back.")
  end

  def perform(batch, client: Comfy.client, llm: Llm.enabled? ? Llm.client : nil)
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
  rescue Remote::Unreachable => e
    batch.wait!(e.message)
    raise
  rescue Comfy::Error => e
    batch.fail!(e.message)
  end
end
