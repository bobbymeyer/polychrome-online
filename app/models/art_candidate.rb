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

    image.attach(io: StringIO.new(client.fetch(images.first)), filename: "#{entry.slug}-#{seed}.png", content_type: "image/png")
    update!(status: "done")
  rescue Comfy::Error => e
    update!(status: "failed", error: e.message)
  end

  # Use this one: it becomes the entry's image, and the batch is cleared.
  def pick!
    raise ArgumentError, "That candidate has no image" unless status == "done" && image.attached?

    entry.adopt_art!(self)
    art_batch.destroy!
  end
end
