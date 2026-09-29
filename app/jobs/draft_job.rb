# frozen_string_literal: true

# Asks the language model for a Draft, away from the request that wanted it.
# A model that can't be reached (its machine asleep) is waited for, and the
# draft says so (ApplicationJob.waits_for_services).
class DraftJob < ApplicationJob
  discard_on ActiveJob::DeserializationError # thrown away or replaced meanwhile
  waits_for_services do |job, error|
    job.arguments.first.update!(status: "failed", error: "#{error.message}. Tried for a day; ask again once it's back.")
  end

  def perform(draft, client: Llm.client)
    draft.run!(client) unless draft.finished?
  end
end
