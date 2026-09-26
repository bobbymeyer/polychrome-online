# frozen_string_literal: true

# The middle layer of an image recipe (docs/HANDOFF.md §8): how one kind of
# book entry is framed in a world ("profile view, full body"), with its own
# negative prompt, LoRAs, size and whether the background is removed.
class ArtType < ApplicationRecord
  belongs_to :world

  validates :kind, inclusion: { in: ArtDirection::KINDS }, uniqueness: { scope: :world_id }
  validates :width, :height, numericality: { only_integer: true, in: 256..2048 }

  def self.defaults_for(kind)
    Comfy.config.fetch(:defaults, {}).fetch(kind.to_sym, {}).to_h.stringify_keys.slice("prompt", "negative", "width", "height", "transparent")
  end

  def loras=(value)
    super(ArtDirection.loras(value))
  end

  LABELS = { "location_template" => "Locations", "encounter_table" => "Encounter tables",
             "generator_table" => "Generator tables", "portrait" => "Portraits" }.freeze

  def label
    LABELS.fetch(kind) { kind.pluralize.humanize }
  end
end
