# frozen_string_literal: true

# A book entry whose image can be generated (docs/HANDOFF.md §8). Its recipe
# is composed from three layers: the world's style, its content type's
# framing, and its own specifics; each layer can add LoRAs.
module Artwork
  extend ActiveSupport::Concern

  included do
    has_many :art_batches, as: :entry, dependent: :destroy
  end

  def art_kind
    model_name.singular
  end

  def art_type
    world.art_type(art_kind)
  end

  def art_loras=(value)
    super(ArtDirection.loras(value))
  end

  # The entry's own layer: its name and specifics (or its description).
  def art_subject
    ArtDirection.join_prompt(name, art_notes.presence || description)
  end

  # The layers as shown in the art studio, top to bottom.
  def art_layers
    type = art_type
    [
      { "label" => world.name, "prompt" => world.art_style, "negative" => world.art_negative, "loras" => world.art_loras },
      { "label" => type.label, "prompt" => type.prompt, "negative" => type.negative, "loras" => type.loras },
      { "label" => name, "prompt" => art_subject, "negative" => nil, "loras" => art_loras }
    ]
  end

  # Everything ComfyUI needs apart from the seed.
  def art_recipe
    type = art_type
    {
      "checkpoint" => world.art_checkpoint.presence || Comfy.config[:checkpoint],
      "loras" => ArtDirection.merge_loras(world.art_loras, type.loras, art_loras),
      "positive" => ArtDirection.join_prompt(world.art_style, type.prompt, art_subject),
      "negative" => ArtDirection.join_prompt(world.art_negative, type.negative),
      "width" => type.width,
      "height" => type.height,
      "transparent" => type.transparent
    }
  end

  def art_batch
    art_batches.order(:id).last
  end

  # Replace the image with a picked candidate, keeping how it was made.
  def adopt_art!(candidate)
    batch = candidate.art_batch
    transaction do
      image.attach(io: StringIO.new(candidate.image.download), filename: "#{slug}-#{candidate.seed}.png",
                   content_type: candidate.image.content_type || "image/png")
      update!(image_seed: candidate.seed, image_prompt: batch.recipe["positive"], image_recipe: batch.recipe)
    end
  end
end
