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
    "dawn" => "each new day",
    "now_and_then" => "now and then, overnight"
  }.freeze
  # What ticked it, as the table hears it.
  REASONS = { "rest" => "the party rested", "travel" => "time on the road", "failed_check" => "a failed check", "dawn" => "a new day", "now_and_then" => "time passing" }.freeze

  include CampaignPages

  belongs_to :campaign
  belongs_to :world_front, optional: true
  belongs_to :location_mode, optional: true
  # The place behind it (a dungeon the goblins raid from): clearing the place
  # stops the clock (Campaign#clear_place!).
  belongs_to :map_node, optional: true

  normalizes :name, with: ->(name) { name.to_s.strip }
  normalizes :full_line, with: ->(line) { line.to_s.strip.presence }

  validates :name, presence: true, length: { maximum: 120 }
  validates :segments, numericality: { only_integer: true, in: 2..12 }
  validates :filled, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :triggers_known
  validate :mode_is_the_locations
  validate :place_is_the_campaigns

  scope :running, -> { where(full_at: nil, stopped_at: nil) }
  scope :shown_to_players, -> { where(public: true) }

  after_commit :broadcast

  def triggers=(value)
    super(Array(value).map(&:to_s).compact_blank.uniq)
  end

  def full?
    !full_at.nil?
  end

  # Stopped for good: the party dealt with what was behind it.
  def stopped?
    !stopped_at.nil?
  end

  def stop!
    return if stopped? || full?

    update!(stopped_at: Time.current)
    campaign.narrate("#{name}: not any more.") if public?
  end

  def ticks_on?(trigger)
    triggers.include?(trigger.to_s)
  end

  # Advance (or, with a negative step, wind back) the clock. Filling it
  # announces the line and switches the location's mode; winding a full
  # clock back leaves the mode as it is (the GM can clear that on the
  # location). reason: what ticked it, for the table's line.
  def tick!(by = 1, reason: nil)
    return self if stopped?

    was_full = full?
    now = (filled + by).clamp(0, segments)
    return self if now == filled

    transaction do
      update!(filled: now, full_at: now == segments ? (full_at || Time.current) : nil)
      if full? && !was_full
        fill!
      elsif public? && by.positive?
        campaign.narrate("#{name}: #{filled} of #{segments}#{" (#{reason})" if reason}.")
      end
    end
    self
  end

  # The place whose mode it sets off when it fills.
  def location = location_mode&.location

  # The mode it sets off, named for the pages.
  def mode_name = location_mode&.name

  private

  def fill!
    line = full_line || ("#{name}: it has happened." if public?)
    # Full when the table heard it, so the recap finds it in that session.
    update!(full_at: campaign.narrate(line).created_at) if line
    location.switch_mode!(location_mode.key) if location_mode && location.current_mode != location_mode
  end

  def place_is_the_campaigns
    errors.add(:map_node, "isn't on this campaign's map") if map_node && map_node.campaign_id != campaign_id
  end

  def triggers_known
    unknown = triggers - TRIGGERS.keys
    errors.add(:triggers, "aren't known: #{unknown.join(', ')}") if unknown.any?
  end

  def mode_is_the_locations
    errors.add(:location_mode, "isn't in this campaign") if location_mode && location.campaign_id != campaign_id
  end

  # The GM's list everywhere it's open, and the players' view of the public
  # clocks (on their own stream, so a hidden clock never reaches them).
  def broadcast
    campaign.broadcast_party_knows
    broadcast_replace_to campaign, :gm, target: "gm_clocks", partial: "campaigns/clocks/gm", locals: { campaign: campaign }
  end
end
