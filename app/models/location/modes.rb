# frozen_string_literal: true

# A place's modes (LocationMode): its other states, prepared by the GM and
# set off at the table. The world doesn't change; the place does, for a
# while.
module Location::Modes
  extend ActiveSupport::Concern

  included do
    # The two point at each other: let go of the current one before the modes go.
    before_destroy(prepend: true) { update_columns(current_mode_id: nil) if current_mode_id }
    has_many :modes, -> { order(:id) }, class_name: "LocationMode", dependent: :destroy, inverse_of: :location
    belongs_to :current_mode, class_name: "LocationMode", optional: true
    validate :current_mode_is_ours
  end

  # The key of the mode it's in, or nil.
  def mode = current_mode&.key

  def service_closed?(kind)
    current_mode&.shuts?(kind) || false
  end

  def encounter_table_for_mode
    current_mode&.encounter_table
  end

  # Prepares a mode. attrs: "name", "line", "description", "closed",
  # "music", "art", and "encounters" (an encounter table's slug).
  def add_mode!(attrs)
    attrs = attrs.to_h.stringify_keys
    name = attrs["name"].to_s.strip
    raise Refusal, "A mode needs a name" if name.empty?
    raise Refusal, "#{view['name']} already has a mode called #{name}" if modes.exists?(key: name.parameterize(separator: "_"))

    table = attrs["encounters"].presence && campaign.world.encounter_tables.find_by(slug: attrs["encounters"])
    modes.create!(attrs.slice("line", "description", "closed", "music", "art").merge("name" => name, "encounter_table" => table))
  end

  def remove_mode!(key)
    transaction do
      chosen = mode_called(key)
      update!(current_mode: nil) if current_mode == chosen
      chosen.destroy!
    end
  end

  # How a mode changes the place's picture (§8): words after the rest of
  # the prompt ("on fire, thick smoke, ash falling").
  def set_mode_art!(key, words)
    mode_called(key).update!(art: words)
  end

  # The place's picture as it is now: the mode's own, if it has one, else
  # the Gazetteer entry's. nil when neither has been made.
  def picture
    in_mode = current_mode&.mode_art
    return in_mode.image if in_mode&.image&.attached?

    location_template.image if location_template.image.attached?
  end

  # Sets the mode off, and tells the table.
  def switch_mode!(key)
    chosen = mode_called(key)
    transaction do
      update!(current_mode: chosen)
      line = chosen.line || "#{view['name']}: #{chosen.name}."
      campaign.narrate(line)
      campaign.start_rumour!(line, at: map_node, seen: campaign.current_node == map_node) if map_node
    end
    campaign.broadcast_music
  end

  # Back to how it was.
  def clear_mode!(line = nil)
    was = current_mode or raise Refusal, "#{view['name']} is as it always was"
    transaction do
      update!(current_mode: nil)
      campaign.narrate(line.to_s.strip.presence || "#{view['name']} is itself again: #{was.name.downcase} no more.")
    end
    campaign.broadcast_music
  end

  def mode_called(key)
    modes.find_by(key: key.to_s) or raise Refusal, "#{view['name']} has no mode called #{key}"
  end

  private

  def current_mode_is_ours
    errors.add(:current_mode, "isn't one of this place's modes") if current_mode && current_mode.location_id != id
  end
end
