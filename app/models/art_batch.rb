# frozen_string_literal: true

# One round of generation for a book entry (docs/HANDOFF.md §8): the composed
# recipe, frozen when the batch starts, and its candidates. Each candidate is
# its own ComfyUI prompt with its own seed. ArtBatchJob submits and collects;
# every change refreshes the pages watching the entry.
class ArtBatch < ApplicationRecord
  STATUSES = %w[queued running done failed].freeze

  belongs_to :world
  belongs_to :entry, polymorphic: true
  has_many :candidates, -> { order(:position) }, class_name: "ArtCandidate", dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  after_commit :refresh_watchers

  # A new batch replaces any earlier one: the strip shows one round at a time.
  def self.start!(entry, count: Comfy.config[:candidates])
    count = count.to_i.clamp(1, 8)
    base = Random.rand(2**31)
    batch = transaction do
      entry.art_batches.destroy_all
      create!(world: entry.world, entry: entry, recipe: entry.art_recipe).tap do |b|
        count.times { |i| b.candidates.create!(position: i, seed: (base + i) % 2**31) }
      end
    end
    ArtBatchJob.perform_later(batch)
    batch
  end

  def finished?
    status.in?(%w[done failed])
  end

  def pending_count
    candidates.count { |c| !c.finished? }
  end

  # Queue every candidate with ComfyUI. ComfyUI runs them one after another.
  def submit!(client)
    candidates.each do |candidate|
      next if candidate.comfy_prompt_id

      graph = Comfy::Graph.build(recipe, seed: candidate.seed, prefix: "polychrome/#{entry.slug}-#{candidate.seed}", settings: graph_settings)
      candidate.update!(comfy_prompt_id: client.submit(graph), status: "running")
    end
    update!(status: "running")
  end

  # Collect whatever has finished. Returns true once every candidate has.
  def collect!(client)
    candidates.reject(&:finished?).each { |candidate| candidate.collect!(client) }
    return false if candidates.reload.any? { |c| !c.finished? }

    if candidates.all? { |c| c.status == "failed" }
      fail!(candidates.first&.error || "Nothing came back")
    else
      update!(status: "done")
    end
    true
  end

  def fail!(message)
    update!(status: "failed", error: message)
    candidates.reject(&:finished?).each { |c| c.update!(status: "failed", error: message) }
  end

  def timed_out?
    created_at < Comfy.config.fetch(:timeout, 900).to_i.seconds.ago
  end

  def refresh_watchers
    entry&.broadcast_refresh_to(entry, :art)
  end

  private

  def graph_settings
    Comfy.config.to_h.stringify_keys.slice("sampler", "scheduler", "steps", "cfg", "rembg_node", "rembg_input")
  end
end
