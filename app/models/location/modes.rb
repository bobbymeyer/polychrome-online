# frozen_string_literal: true

# Modes: the place's other states. A mode is prepared by the GM and set off
# at the table: the city burns, the mine floods, the festival starts. While
# it lasts, some services are shut, the music changes, there can be trouble
# on arrival (an encounter table), and players read a line about it. The
# world doesn't change.
#
#   { "key" => "burning", "name" => "Burning", "line" => "Smoke over the rooftops: Tule is burning.",
#     "description" => "Half the market is ash.", "closed" => ["shop"], "music" => "battle",
#     "encounters" => "town_riot" }
module Location::Modes
  extend ActiveSupport::Concern

  included do
    validate :modes_are_modes
  end

  def current_mode
    modes.find { |t| t["key"] == mode } if mode
  end

  def service_closed?(kind)
    Array(current_mode&.dig("closed")).include?(kind.to_s)
  end

  def encounter_table_for_mode
    slug = current_mode&.dig("encounters")
    slug && campaign.world.encounter_tables.find_by(slug: slug)
  end

  def add_mode!(attrs)
    name = attrs["name"].to_s.strip
    raise Refusal, "A mode needs a name" if name.empty?

    key = name.parameterize(separator: "_")
    raise Refusal, "#{view['name']} already has a mode called #{name}" if modes.any? { |t| t["key"] == key }

    entry = { "key" => key, "name" => name, "line" => attrs["line"].to_s.strip.presence, "description" => attrs["description"].to_s.strip.presence,
             "closed" => Array(attrs["closed"]).compact_blank, "music" => attrs["music"].presence,
             "encounters" => attrs["encounters"].presence, "art" => attrs["art"].to_s.strip.presence }.compact
    update!(modes: modes + [ entry ])
  end

  def remove_mode!(key)
    transaction do
      mode_arts.where(mode_key: key).destroy_all
      update!(modes: modes.reject { |t| t["key"] == key }, mode: (mode unless mode == key))
    end
  end

  # How a mode changes the place's picture (§8): words after the rest of
  # the prompt ("on fire, thick smoke, ash falling").
  def set_mode_art!(key, words)
    raise Refusal, "#{name} has no mode called #{key}" unless modes.any? { |t| t["key"] == key }

    update!(modes: modes.map { |t| t["key"] == key ? t.merge("art" => words.to_s.strip.presence).compact : t })
  end

  # The place's picture as it is now: the mode's own, if it has one, else
  # the Gazetteer entry's. nil when neither has been made.
  def picture
    in_mode = current_mode && mode_arts.find_by(mode_key: mode)
    return in_mode.image if in_mode&.image&.attached?

    location_template.image if location_template.image.attached?
  end

  # Sets the mode off, and tells the table.
  def switch_mode!(key)
    chosen = modes.find { |t| t["key"] == key } or raise Refusal, "#{view['name']} has no mode called #{key}"
    transaction do
      update!(mode: key)
      campaign.narrate(chosen["line"] || "#{view['name']}: #{chosen['name']}.")
    end
    campaign.broadcast_map
    campaign.broadcast_music
  end

  # Back to how it was.
  def clear_mode!(line = nil)
    was = current_mode or raise Refusal, "#{view['name']} is as it always was"
    transaction do
      update!(mode: nil)
      campaign.narrate(line.to_s.strip.presence || "#{view['name']} is itself again: #{was['name'].downcase} no more.")
    end
    campaign.broadcast_map
    campaign.broadcast_music
  end

  private

  def modes_are_modes
    world = campaign&.world or return
    Array(modes).each do |t|
      errors.add(:modes, "#{t['name']}: music must be one of #{Campaign::MUSIC_CHOICES.join(', ')}") if t["music"] && !Campaign::MUSIC_CHOICES.include?(t["music"])
      errors.add(:modes, "#{t['name']}: #{t['encounters']} isn't an encounter table") if t["encounters"] && !world.encounter_tables.exists?(slug: t["encounters"])
    end
    errors.add(:mode, "isn't one of this place's modes") if mode && Array(modes).none? { |t| t["key"] == mode }
  end
end
