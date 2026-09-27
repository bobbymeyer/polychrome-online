# frozen_string_literal: true

# Anything with an image slot that can be generated (docs/HANDOFF.md §8):
# book entries and speaker portraits. The recipe is composed in layers: the
# world's style, the content type's framing, the subject's specifics, and for
# a portrait its expression. The world, type and subject layers can each
# name a model (the lowest one that does wins) and stack LoRAs.
#
# Book entries use the defaults below; Portrait overrides the hooks.
module Artwork
  extend ActiveSupport::Concern

  included do
    has_many :art_batches, as: :entry, dependent: :destroy
  end

  # --- hooks -------------------------------------------------------------------

  def art_kind = model_name.singular
  # What the image is, in a sentence ("Goblin", "Cid's happy portrait").
  def art_title = name
  def art_world = world
  # Where the page watching this art subscribes (ArtBatch refreshes it).
  def art_stream = self
  def art_filename(seed) = "#{slug}-#{seed}.png"
  def art_subject_label = name
  def art_subject = ArtDirection.join_prompt(name, art_notes.presence || description)
  def art_subject_loras = art_loras
  def art_subject_model = art_model
  # A layer after the subject, if any (a portrait's expression).
  def art_detail = nil
  # A seed to try first, for a consistent look (a portrait's neutral seed).
  def art_seed_hint = nil

  # -----------------------------------------------------------------------------

  def art_loras=(value)
    super(ArtDirection.loras(value))
  end

  def art_type
    art_world.art_type(art_kind)
  end

  # The layers as shown in the art studio, top to bottom.
  def art_layers
    world = art_world
    type = art_type
    layers = [
      { "label" => world.name, "role" => "World", "prompt" => world.art_style, "model" => world.art_model, "loras" => world.art_loras },
      { "label" => type.label, "role" => "Type", "prompt" => type.prompt, "model" => type.model, "loras" => type.loras },
      { "label" => art_subject_label, "role" => "Subject", "prompt" => art_subject, "model" => art_subject_model, "loras" => art_subject_loras }
    ]
    layers << { "label" => art_detail[:label], "role" => "Detail", "prompt" => art_detail[:prompt], "loras" => [] } if art_detail
    layers
  end

  def art_model_name
    type = art_type
    ArtDirection.pick_model(art_subject_model, type.model, art_world.art_model, Comfy.config[:model])
  end

  # Everything ComfyUI needs apart from the seed. The family of the model
  # decides the quality words that lead the prompt, whether there is a
  # negative prompt at all, and the size (scaled into its trained range).
  # The parts are kept so the subject can be rewritten (PromptWriter) and
  # the prompt put back together.
  def art_recipe
    world = art_world
    type = art_type
    model = art_model_name
    family = Comfy::Family.for(model, capabilities: -> { Comfy.capabilities })
    parts = { "prefix" => family.prefix, "style" => world.art_style.to_s, "framing" => type.prompt.to_s,
              "subject" => art_subject.to_s, "detail" => art_detail&.dig(:prompt).to_s }
    width, height = family.size(type.width, type.height)
    {
      "model" => model,
      "family" => family.slug,
      "loras" => ArtDirection.stack_loras(world.art_loras, type.loras, art_subject_loras),
      "positive" => ArtDirection.compose(parts),
      "negative" => family.negative? ? ArtDirection.join_prompt(family.negative_prefix, world.art_negative, type.negative) : "",
      "width" => width,
      "height" => height,
      "transparent" => type.transparent,
      "parts" => parts
    }
  end

  def art_batch
    art_batches.order(:id).last
  end

  # Replace the image with a picked candidate, keeping how it was made.
  def adopt_art!(candidate)
    batch = candidate.art_batch
    transaction do
      image.attach(io: StringIO.new(candidate.image.download), filename: art_filename(candidate.seed),
                   content_type: candidate.image.content_type || "image/png")
      update!(image_seed: candidate.seed, image_prompt: batch.recipe["positive"], image_recipe: batch.recipe)
    end
  end
end
