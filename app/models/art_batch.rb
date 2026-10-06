# frozen_string_literal: true

# One round of generation for a book entry (docs/HANDOFF.md §8): the composed
# recipe, frozen when the batch starts, and its candidates. Each candidate is
# its own ComfyUI prompt with its own seed. ArtBatchJob submits and collects
# (ComfyRun); every change refreshes the pages watching the entry.
class ArtBatch < ApplicationRecord
  include ComfyRun

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
  # draft: quick previews (fewer steps, smaller, cut out like the full
  # render would be), to be made properly with #refine!.
  # source: an image to redraw from instead of starting blank (the chain,
  # Headshot): { "kind" => "sprite" | "portrait", "id" => n }, re-noised
  # by denoise; it is put in ComfyUI's inputs when the batch runs.
  def self.start!(entry, count: Comfy.config[:candidates], write: true, transparent: nil, draft: false, source: nil, denoise: nil)
    count = count.to_i.clamp(1, 8)
    base = Random.rand(2**31)
    seeds = Array.new(count) { |i| (base + i) % 2**31 }
    seeds[0] = entry.art_seed_hint if entry.art_seed_hint
    batch = transaction do
      entry.art_batches.destroy_all
      recipe = entry.art_recipe.merge("write" => write && Llm.enabled?)
      recipe["transparent"] = transparent unless transparent.nil?
      recipe = recipe.merge("source" => source, "denoise" => denoise.to_f.clamp(0.1, 1.0)) if source
      if recipe["transparent"]
        recipe["cutout"] = Cutout.label # the removal model, in ComfyUI
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

  # A recipe made quick: the family's draft steps and size. The background
  # comes off a draft too, since a draft can be used as it is. What the
  # full render needs is kept.
  def self.draft_of(recipe)
    family = Comfy::Family.new(recipe["family"], recipe["model"])
    width, height = family.draft_size(recipe["width"], recipe["height"])
    recipe.merge("draft" => true, "steps" => family.draft_steps, "width" => width, "height" => height,
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

  # What starts from an image (a refinement from its draft, a chain step
  # from the sprite's head or the Neutral portrait) has it put in ComfyUI's
  # inputs first.
  def upload_source!(client)
    return if recipe["source_image"]

    bytes, name = source_bytes
    return unless bytes

    update!(recipe: recipe.merge("source_image" => client.upload(bytes, name)))
  end

  # [bytes, a name for ComfyUI's inputs], or nil when the batch starts blank.
  def source_bytes
    if recipe["refines"]
      source = ArtCandidate.find_by(id: recipe.dig("refines", "candidate_id"))
      raise Comfy::Error, "The draft to refine is gone" unless source&.image&.attached?

      # As rendered, on its ground: the cut-out's colours are the render's.
      [ Cutout.opaque(source.image.download), "polychrome-draft-#{source.id}-#{source.seed}.png" ]
    elsif (source = recipe["source"])
      case source["kind"]
      when "sprite"
        sprite = Sprite.find_by(id: source["id"])
        raise Comfy::Error, "The sprite to draw the portrait from is gone" unless sprite&.image&.attached?

        [ Headshot.of(sprite.image.download), "polychrome-head-#{sprite.id}-#{sprite.image_seed}.png" ]
      when "portrait"
        portrait = Portrait.find_by(id: source["id"])
        raise Comfy::Error, "The Neutral portrait to draw from is gone" unless portrait&.image&.attached?

        [ portrait.image.download, "polychrome-face-#{portrait.id}-#{portrait.image_seed}.png" ]
      end
    end
  end

  # Where a chain step starts from, for the strip ("from the sprite").
  def source_label
    case recipe.dig("source", "kind")
    when "sprite" then "from the sprite"
    when "portrait" then "from the Neutral portrait"
    end
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

  # The batch fails with its candidates still out (ComfyRun).
  def fail!(message)
    super
    candidates.reject(&:finished?).each { |c| c.update!(status: "failed", error: message) }
  end

  # When ComfyUI took it; a batch made before ComfyUI could be reached counts from when it was made.
  def comfy_started_at = submitted_at || created_at

  # Only the art section reloads (app/javascript/stream_actions.js), so a
  # form being typed into elsewhere on the page is left alone.
  def refresh_watchers
    stream = entry&.art_stream
    Turbo::StreamsChannel.broadcast_action_to(stream, :art, action: :reload_frame, target: "art_panel") if stream
  end
end
