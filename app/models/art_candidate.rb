# frozen_string_literal: true

# One generated image in a batch, with the seed that made it.
class ArtCandidate < ApplicationRecord
  STATUSES = %w[queued running done failed].freeze

  belongs_to :art_batch
  has_one_attached :image

  validates :status, inclusion: { in: STATUSES }

  # Each image refreshes the pages watching the entry as it lands.
  after_update_commit -> { art_batch.refresh_watchers }

  delegate :entry, to: :art_batch

  def finished?
    status.in?(%w[done failed])
  end

  def collect!(client)
    return unless comfy_prompt_id

    images = client.result(comfy_prompt_id)
    return if images.nil?
    return update!(status: "failed", error: "The workflow saved no image") if images.empty?

    bytes = client.fetch(images.first)
    image.attach(io: StringIO.new(bytes), filename: entry.art_filename(seed), content_type: "image/png")
    # Asked to lose its background: did it? (A removal node can fail quietly.)
    wanted = art_batch.recipe["transparent"]
    update!(status: "done", transparent: (Comfy::BackgroundRemoval.png_alpha?(bytes) if wanted),
            run_seconds: client.respond_to?(:run_seconds) ? client.run_seconds(comfy_prompt_id) : nil)
  rescue Comfy::Unreachable
    raise # not this image's fault: the batch waits for ComfyUI (ArtBatchJob)
  rescue Comfy::Error => e
    update!(status: "failed", error: e.message)
  end

  # Use this one: it becomes the entry's image, and the batch is cleared.
  def pick!
    raise Refusal, "That candidate has no image" unless status == "done" && image.attached?

    entry.adopt_art!(self)
    art_batch.drafts&.destroy!
    art_batch.destroy!
  end
end
