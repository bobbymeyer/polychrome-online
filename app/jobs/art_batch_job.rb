# frozen_string_literal: true

# Drives an ArtBatch (docs/HANDOFF.md §8): submits its candidates to ComfyUI,
# then checks back every few seconds and collects each image as it lands,
# until all are in, the batch fails, or it times out. It re-enqueues itself
# rather than sleeping, so it never holds a worker while ComfyUI renders.
class ArtBatchJob < ApplicationJob
  POLL = 3.seconds

  discard_on ActiveJob::DeserializationError # the batch was discarded or replaced

  def perform(batch, client: Comfy.client, llm: Llm.enabled? ? Llm.client : nil)
    return if batch.finished?

    if batch.status == "queued"
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
  rescue Comfy::Error => e
    batch.fail!(e.message)
  end
end
