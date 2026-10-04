# frozen_string_literal: true

# One round of generation for a book entry (docs/HANDOFF.md §8): the composed
# recipe, frozen when the batch starts, and its candidates. Each candidate is
# its own ComfyUI prompt with its own seed. ArtBatchJob submits and collects;
# every change refreshes the pages watching the entry.
class ArtBatch < ApplicationRecord
  # waiting: ComfyUI couldn't be reached; ArtBatchJob tries again later.
  STATUSES = %w[queued waiting running done failed].freeze

  belongs_to :world
  belongs_to :entry, polymorphic: true
  has_many :candidates, -> { order(:position) }, class_name: "ArtCandidate", dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  after_commit :refresh_watchers

  # A new batch replaces any earlier one: the strip shows one round at a time.
  # The first candidate tries the entry's seed hint when it has one (a
  # portrait's neutral seed), so a face stays closer across expressions.
  # write: let the language model (if there is one) rewrite the subject.
  # transparent: remove the background, or keep it, whatever the type says.
  # draft: quick previews (fewer steps, smaller, background left for the
  # full render), to be made properly with #refine!.
  def self.start!(entry, count: Comfy.config[:candidates], write: true, transparent: nil, draft: false)
    count = count.to_i.clamp(1, 8)
    base = Random.rand(2**31)
    seeds = Array.new(count) { |i| (base + i) % 2**31 }
    seeds[0] = entry.art_seed_hint if entry.art_seed_hint
    batch = transaction do
      entry.art_batches.destroy_all
      recipe = entry.art_recipe.merge("write" => write && Llm.enabled?)
      recipe["transparent"] = transparent unless transparent.nil?
      if recipe["transparent"] && Cutout.enabled?
        recipe["cutout"] = Cutout.label
        recipe = Cutout.on_ground(recipe) # rendered on the ground the cut-out keys against, not white
      end
      recipe = draft_of(recipe) if draft
      create!(world: entry.art_world, entry: entry, recipe: recipe).tap do |b|
        seeds.each_with_index { |seed, i| b.candidates.create!(position: i, seed: seed) }
      end
    end
    ArtBatchJob.perform_later(batch)
    batch
  end

  # A recipe made quick: the family's draft steps and size, no background
  # removal yet. What the full render needs is kept.
  def self.draft_of(recipe)
    family = Comfy::Family.new(recipe["family"], recipe["model"])
    width, height = family.draft_size(recipe["width"], recipe["height"])
    recipe.merge("draft" => true, "steps" => family.draft_steps, "width" => width, "height" => height, "transparent" => false,
                 "full" => recipe.slice("width", "height", "transparent"))
  end

  def draft? = recipe["draft"] == true

  # Make one draft properly: the same prompt and seed at full size and
  # steps, starting from the draft image so it stays the same picture. A
  # new batch of one; the drafts stay on the page beside it.
  def self.refine!(candidate)
    batch = candidate.art_batch
    raise Refusal, "Only a draft can be made properly" unless batch.draft?
    raise Refusal, "That draft has no image yet" unless candidate.status == "done" && candidate.image.attached?

    family = Comfy::Family.new(batch.recipe["family"], batch.recipe["model"])
    recipe = batch.recipe.except("draft", "steps", "full", "workflow").merge(batch.recipe["full"])
                  .merge("write" => false, "refines" => { "batch_id" => batch.id, "candidate_id" => candidate.id }, "denoise" => family.refine_denoise)
    refinement = transaction do
      batch.entry.art_batches.where.not(id: batch.id).destroy_all
      create!(world: batch.world, entry: batch.entry, recipe: recipe).tap { |b| b.candidates.create!(position: 0, seed: candidate.seed) }
    end
    ArtBatchJob.perform_later(refinement)
    refinement
  end

  # The drafts a refinement came from, while they're still here.
  def drafts
    ArtBatch.find_by(id: recipe.dig("refines", "batch_id")) if recipe["refines"]
  end

  # A refinement starts from its draft's image, put in ComfyUI's inputs.
  def upload_source!(client)
    return unless recipe["refines"] && !recipe["source_image"]

    source = ArtCandidate.find_by(id: recipe.dig("refines", "candidate_id"))
    raise Comfy::Error, "The draft to refine is gone" unless source&.image&.attached?

    name = client.upload(source.image.download, "polychrome-draft-#{source.id}-#{source.seed}.png")
    update!(recipe: recipe.merge("source_image" => name))
  end

  def finished?
    status.in?(%w[done failed])
  end

  def pending_count
    candidates.count { |c| !c.finished? }
  end

  # Before anything is queued: the language model's go at the subject, when
  # asked for. Every candidate then shares one prompt, so an image model
  # that caches its text encodings only encodes it once.
  def write_prompt!(llm)
    return unless recipe["write"] && !recipe.dig("parts", "written") && !recipe["writer_error"]

    update!(recipe: PromptWriter.rewrite(recipe, client: llm, world: world))
  end

  # Queue every candidate with ComfyUI, each graph built against what this
  # ComfyUI has installed. ComfyUI runs them one after another, keeping the
  # loaded model and encoded prompt between them.
  def submit!(client)
    capabilities = client.capabilities
    unless capabilities.reachable?
      raise (capabilities.offline? ? Comfy::Unreachable : Comfy::Error), capabilities.error || "ComfyUI isn't answering"
    end

    candidates.each do |candidate|
      next if candidate.comfy_prompt_id

      prefix = "polychrome/#{entry.art_filename(candidate.seed).delete_suffix('.png')}"
      graph = Comfy::Workflow.build(recipe, seed: candidate.seed, prefix: prefix, capabilities: capabilities)
      update!(recipe: recipe.merge("workflow" => Comfy::Workflow.outline(graph))) unless recipe["workflow"]
      candidate.update!(comfy_prompt_id: client.submit(graph), status: "running")
    end
    update!(status: "running", error: nil, submitted_at: submitted_at || Time.current)
  end

  # Collect whatever has finished. Returns true once every candidate has.
  def collect!(client, cutout: Cutout.client)
    candidates.reject(&:finished?).each { |candidate| candidate.collect!(client, cutout: cutout) }
    return false if candidates.reload.any? { |c| !c.finished? }

    if candidates.all? { |c| c.status == "failed" }
      fail!(candidates.first&.error || "Nothing came back")
    else
      update!(status: "done")
    end
    true
  end

  # ComfyUI couldn't be reached: say so, and keep everything for the retry.
  def wait!(message)
    update!(status: "waiting", error: message)
  end

  def fail!(message)
    update!(status: "failed", error: message)
    candidates.reject(&:finished?).each { |c| c.update!(status: "failed", error: message) }
  end

  # Rendering has taken too long (counted from when ComfyUI took it: a
  # batch waiting for ComfyUI to come back isn't timing out).
  def timed_out?
    (submitted_at || created_at) < Comfy.config.fetch(:timeout, 900).to_i.seconds.ago
  end

  # Only the art section reloads (app/javascript/stream_actions.js), so a
  # form being typed into elsewhere on the page is left alone.
  def refresh_watchers
    stream = entry&.art_stream
    Turbo::StreamsChannel.broadcast_action_to(stream, :art, action: :reload_frame, target: "art_panel") if stream
  end
end
