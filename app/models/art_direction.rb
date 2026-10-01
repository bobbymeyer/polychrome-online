# frozen_string_literal: true

# Helpers for composing an image recipe in layers (docs/HANDOFF.md §8): the
# world's house style, the content type's framing, the entry's specifics.
module ArtDirection
  # The book (route namespace) each kind of book entry lives in.
  BOOKS = { "monster" => :bestiary, "job" => :compendium, "item" => :armory, "ability" => :grimoire,
            "location_template" => :gazetteer, "encounter_table" => :encounters }.freeze

  # Every kind of image slot: the books, and speaker portraits.
  KINDS = (BOOKS.keys + %w[portrait beat]).freeze

  module_function

  OFF = [ false, "0", "false", "off" ].freeze

  # [{ "name", "strength", "on" }] from form rows or JSON: blank names
  # dropped, strength a float (default 1.0) kept within ComfyUI's usual
  # range, on unless switched off.
  def loras(value)
    rows = value.is_a?(Hash) ? value.values : Array(value)
    rows.filter_map do |row|
      row = row.to_h.stringify_keys
      name = row["name"].to_s.strip
      next if name.empty?

      strength = row["strength"].to_s.strip.empty? ? 1.0 : row["strength"].to_f
      { "name" => name, "strength" => strength.clamp(-5.0, 5.0).round(2), "on" => !OFF.include?(row.fetch("on", true)) }
    end
  end

  # The LoRAs stacked in layer order, world first. A LoRA a later layer
  # names again keeps its place in the stack and takes the later layer's
  # strength and switch: that is how an entry turns a world LoRA down or off.
  # Every LoRA is kept, on or off, so the pages can show what was switched off.
  def stack_loras(*layers)
    layers.flat_map { |layer| loras(layer) }
          .each_with_object({}) { |lora, by_name| by_name[lora["name"]] = lora }
          .values
  end

  def active_loras(stack)
    stack.select { |lora| lora["on"] && !lora["strength"].zero? }
  end

  # The model from the lowest layer that names one: entry, then type, then
  # world, then the configured default.
  def pick_model(*layers_bottom_up)
    layers_bottom_up.map { |model| model.to_s.strip }.find { |model| !model.empty? }
  end

  # The prompt from a recipe's parts, in layer order.
  def compose(parts)
    join_prompt(*parts.values_at("prefix", "style", "framing", "subject", "detail"))
  end

  def join_prompt(*parts)
    parts.map { |part| part.to_s.strip.delete_suffix(",").strip }.reject(&:empty?).join(", ")
  end
end
