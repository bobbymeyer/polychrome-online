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

  def collect!(client, cutout: Cutout.client)
    return unless comfy_prompt_id

    images = client.result(comfy_prompt_id)
    return if images.nil?
    return update!(status: "failed", error: "The workflow saved no image") if images.empty?

    bytes = client.fetch(images.first)
    # Asked to lose its background: the background remover takes it off
    # (Cutout). Did it? (A model can leave it.) If the remover turns it
    # down, the picture is kept, background and all, with the reason.
    wanted = art_batch.recipe["transparent"]
    kept = nil
    if wanted && Cutout.enabled?
      begin
        bytes = Cutout.remove(bytes, client: cutout)
      rescue Cutout::Unreachable
        raise
      rescue Cutout::Error => e
        kept = e.message
      end
    end
    image.attach(io: StringIO.new(bytes), filename: entry.art_filename(seed), content_type: "image/png")
    update!(status: "done", transparent: (Cutout.png_alpha?(bytes) if wanted), error: kept,
            run_seconds: client.respond_to?(:run_seconds) ? client.run_seconds(comfy_prompt_id) : nil)
  rescue Comfy::Unreachable, Cutout::Unreachable
    raise # not this image's fault: the batch waits for the service (ArtBatchJob)
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
