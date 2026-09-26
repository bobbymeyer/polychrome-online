# frozen_string_literal: true

# Helpers for composing an image recipe in layers (docs/HANDOFF.md §8): the
# world's house style, the content type's framing, the entry's specifics.
module ArtDirection
  KINDS = %w[monster job item ability location_template].freeze

  # The book (route namespace) each kind of entry lives in.
  BOOKS = { "monster" => :bestiary, "job" => :compendium, "item" => :armory,
            "ability" => :grimoire, "location_template" => :gazetteer }.freeze

  module_function

  # [{ "name", "strength" }] from form rows or JSON: blank names dropped,
  # strength a float (default 1.0) kept within ComfyUI's usual range.
  def loras(value)
    rows = value.is_a?(Hash) ? value.values : Array(value)
    rows.filter_map do |row|
      row = row.to_h.stringify_keys
      name = row["name"].to_s.strip
      next if name.empty?

      strength = row["strength"].to_s.strip.empty? ? 1.0 : row["strength"].to_f
      { "name" => name, "strength" => strength.clamp(-5.0, 5.0).round(2) }
    end
  end

  # Later layers win: an entry can turn a world LoRA down, or off with 0.
  def merge_loras(*layers)
    layers.flat_map { |layer| loras(layer) }
          .each_with_object({}) { |lora, by_name| by_name[lora["name"]] = lora }
          .values.reject { |lora| lora["strength"].zero? }
  end

  def join_prompt(*parts)
    parts.map { |part| part.to_s.strip.delete_suffix(",").strip }.reject(&:empty?).join(", ")
  end
end
