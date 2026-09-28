# frozen_string_literal: true

# A clock (a front): something that happens if the party doesn't stop it,
# in segments. "The Brass Syndicate takes the docks", six segments. The GM
# ticks it, or it ticks itself on what the party does (a rest, a journey, a
# failed check), so dawdling costs something. When it fills, the table hears
# the line, and a location can switch mode: the city burns because the
# party took too long, not because the GM said so.
#
# A public clock is on the table for everyone to watch; a hidden one is the
# GM's alone until it fills.
class Clock < ApplicationRecord
  TRIGGERS = {
    "rest" => "each rest",
    "travel" => "each journey",
    "failed_check" => "each failed check",
    "dawn" => "each new day"
  }.freeze
  # What ticked it, as the table hears it.
  REASONS = { "rest" => "the party rested", "travel" => "time on the road", "failed_check" => "a failed check", "dawn" => "a new day" }.freeze

  belongs_to :campaign
  belongs_to :world_front, optional: true
  belongs_to :location, optional: true

  normalizes :name, with: ->(name) { name.to_s.strip }
  normalizes :full_line, with: ->(line) { line.to_s.strip.presence }
  normalizes :mode_key, with: ->(key) { key.to_s.strip.presence }

  validates :name, presence: true, length: { maximum: 120 }
  validates :segments, numericality: { only_integer: true, in: 2..12 }
  validates :filled, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :triggers_known
  validate :mode_is_the_locations

  scope :running, -> { where(full_at: nil) }
  scope :shown_to_players, -> { where(public: true) }

  after_commit :broadcast

  def triggers=(value)
    super(Array(value).map(&:to_s).compact_blank.uniq)
  end

  def full?
    !full_at.nil?
  end

  def ticks_on?(trigger)
    triggers.include?(trigger.to_s)
  end

  # Advance (or, with a negative step, wind back) the clock. Filling it
  # announces the line and switches the location's mode; winding a full
  # clock back leaves the mode as it is (the GM can clear that on the
  # location). reason: what ticked it, for the table's line.
  def tick!(by = 1, reason: nil)
    was_full = full?
    now = (filled + by).clamp(0, segments)
    return self if now == filled

    transaction do
      update!(filled: now, full_at: now == segments ? (full_at || Time.current) : nil)
      if full? && !was_full
        fill!
      elsif public? && by.positive?
        campaign.messages.create!(kind: "system", body: "#{name}: #{filled} of #{segments}#{" (#{reason})" if reason}.")
      end
    end
    self
  end

  # A mode to switch to, named for the pages.
  def mode_name
    location&.modes&.find { |m| m["key"] == mode_key }&.dig("name")
  end

  private

  def fill!
    line = full_line || ("#{name}: it has happened." if public?)
    # Full when the table heard it, so the recap finds it in that session.
    update!(full_at: campaign.messages.create!(kind: "system", body: line).created_at) if line
    location.switch_mode!(mode_key) if location && mode_key && location.mode != mode_key
  end

  def triggers_known
    unknown = triggers - TRIGGERS.keys
    errors.add(:triggers, "aren't known: #{unknown.join(', ')}") if unknown.any?
  end

  def mode_is_the_locations
    return unless mode_key

    if !location
      errors.add(:mode_key, "needs a location")
    elsif location.campaign_id != campaign_id
      errors.add(:location, "isn't in this campaign")
    elsif location.modes.none? { |m| m["key"] == mode_key }
      errors.add(:mode_key, "isn't one of #{location.name}'s modes")
    end
  end

  # The GM's list everywhere it's open, and the players' view of the public
  # clocks (on their own stream, so a hidden clock never reaches them).
  def broadcast
    { false => :map, true => :map_gm }.each do |gm, stream|
      broadcast_replace_to campaign, stream, target: "party_knows", partial: "tables/party_knows", locals: { campaign: campaign, gm: gm }
    end
    broadcast_replace_to campaign, :map_gm, target: "gm_clocks", partial: "clocks/gm", locals: { campaign: campaign }
  end
end
