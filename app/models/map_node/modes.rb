# frozen_string_literal: true

# A place's modes (LocationMode): its other states, prepared by the GM. Any
# place on the map has them: a town, a dungeon, a landmark, the wilds. One
# can be set off at the table (the current mode); others come on by
# themselves when the calendar says (by night, in winter). They layer: the
# place is in all of them at once, the table's first. The world doesn't
# change; the place does, for a while.
module MapNode::Modes
  extend ActiveSupport::Concern

  included do
    # The two point at each other: let go of the current one before the modes go.
    before_destroy(prepend: true) { update_columns(current_mode_id: nil) if current_mode_id }
    has_many :modes, -> { order(:id) }, class_name: "LocationMode", dependent: :destroy, inverse_of: :map_node
    belongs_to :current_mode, class_name: "LocationMode", optional: true
    validate :current_mode_is_ours
  end

  # The key of the mode the table set it in, or nil.
  def mode = current_mode&.key

  # The modes the calendar brings on at a time.
  def timed_modes_at(day, period)
    almanac = campaign.world.almanac
    modes.select { |mode| mode.timed? && almanac.on?(mode.times, day, period) }
  end

  # The modes it's in now: the one set off at the table, then the calendar's.
  def modes_on(day: campaign.day, period: campaign.time_of_day)
    [ current_mode, *timed_modes_at(day, period) ].compact.uniq
  end

  # The mode that shuts a service (or its things to do: "pastimes"), or nil.
  def shut_by(kind) = modes_on.find { |mode| mode.shuts?(kind) }

  def service_closed?(kind) = shut_by(kind).present?

  # The mode with trouble waiting in it, or nil.
  def troubled_by(**at) = modes_on(**at).find(&:encounter_table)

  def encounter_table_for_mode = troubled_by&.encounter_table

  # The music of the modes it's in, the table's first.
  def mode_music = modes_on.find(&:music)&.music

  # Prepares a mode. attrs: "name", "line", "description", "closed",
  # "music", "art", "times" (when it comes on by itself), "activities"
  # (things to do while it's on), and "encounters" (an encounter table's slug).
  def add_mode!(attrs)
    attrs = attrs.to_h.stringify_keys
    name = attrs["name"].to_s.strip
    raise Refusal, "A mode needs a name" if name.empty?
    raise Refusal, "#{name} already has a mode called #{name}" if modes.exists?(key: name.parameterize(separator: "_"))

    table = attrs["encounters"].presence && campaign.world.encounter_tables.find_by(slug: attrs["encounters"])
    modes.create!(attrs.slice("line", "description", "closed", "music", "art", "times", "activities").merge("name" => name, "encounter_table" => table))
  end

  def remove_mode!(key)
    transaction do
      chosen = mode_called(key)
      update!(current_mode: nil) if current_mode == chosen
      chosen.destroy!
    end
  end

  # Sets the mode off, and tells the table.
  def switch_mode!(key)
    chosen = mode_called(key)
    transaction do
      update!(current_mode: chosen)
      line = chosen.line || "#{name}: #{chosen.name}."
      campaign.narrate(line)
      campaign.start_rumour!(line, at: self, seen: party_here?)
    end
    campaign.broadcast_music
  end

  # The calendar turns: modes with times come on and go. Only the party,
  # where it is, hears what came on (unless it's arriving: Campaign#how_it_is_here!
  # says it all then).
  def follow_the_hours!(was_day, was_period, quiet: false)
    before = timed_modes_at(was_day, was_period)
    now = timed_modes_at(campaign.day, campaign.time_of_day)
    return if before == now

    location&.broadcast_refresh_later
    return unless party_here?

    (now - before).each { |mode| campaign.narrate(mode.line || "#{name}: #{mode.name}.") } unless quiet
    campaign.broadcast_music
  end

  # Back to how it was.
  def clear_mode!(line = nil)
    was = current_mode or raise Refusal, "#{name} is as it always was"
    transaction do
      update!(current_mode: nil)
      campaign.narrate(line.to_s.strip.presence || "#{name} is itself again: #{was.name.downcase} no more.")
    end
    campaign.broadcast_music
  end

  def mode_called(key)
    modes.find_by(key: key.to_s) or raise Refusal, "#{name} has no mode called #{key}"
  end

  private

  def current_mode_is_ours
    errors.add(:current_mode, "isn't one of this place's modes") if current_mode && current_mode.map_node_id != id
  end
end
