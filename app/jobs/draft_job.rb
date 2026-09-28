# frozen_string_literal: true

# Asks the language model for a Draft, away from the request that wanted it.
class DraftJob < ApplicationJob
  discard_on ActiveJob::DeserializationError # thrown away or replaced meanwhile

  def perform(draft, client: Llm.client)
    draft.run!(client) unless draft.finished?
  end
end
