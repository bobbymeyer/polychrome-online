# frozen_string_literal: true

# How something is drawn (docs/HANDOFF.md §8): the subject's own layer of
# the recipe (its notes, LoRAs and model) and, once it has a generated
# picture, the seed, prompt and recipe that made it. One per book entry,
# speaker, portrait or mode picture that has any (Drawn).
class Art < ApplicationRecord
  belongs_to :subject, polymorphic: true

  def loras=(value)
    super(ArtDirection.loras(value))
  end
end
