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
  # The events it can tick on (Campaign::Happenings), as the GM picks them.
  TRIGGERS = {
    "rest" => "each rest",
    "travel" => "each journey",
    "failed_check" => "each failed check",
    "dawn" => "each new day",
    "now_and_then" => "now and then, overnight"
  }.freeze

  include CampaignPages

  belongs_to :campaign
  belongs_to :world_front, optional: true
  belongs_to :mode, optional: true
  # The place behind it (a dungeon the goblins raid from): clearing the place
  # stops the clock (Campaign#clear_place!).
  belongs_to :map_node, optional: true

  normalizes :name, with: ->(name) { name.to_s.strip }
  normalizes :full_line, :impulse, :portents, with: ->(text) { text.to_s.strip.presence }

  validates :name, presence: true, length: { maximum: 120 }
  validates :segments, numericality: { only_integer: true, in: 2..12 }
  validates :filled, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :triggers_known
  validate :times_in_the_calendar, if: :will_save_change_to_times?
  validate :mode_is_the_locations
  validate :place_is_the_campaigns
  validates :impulse, length: { maximum: 200 }
  validate { Portent.parse(portents).last.each { |problem| errors.add(:portents, problem) } }

  scope :running, -> { where(full_at: nil, stopped_at: nil) }
  scope :shown_to_players, -> { where(public: true) }
  # One box from full: the one thing the table needs to know about a clock.
  scope :nearly_full, -> { where("segments - filled = 1") }

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

  # Words from the calendar it keeps to, as modes and things to do do
  # (Pointcrawl::Calendar#on?): "Monday", "winter". None: any time.
  def times=(words)
    super(Array(words).map { |word| word.to_s.strip }.reject(&:empty?).uniq(&:downcase))
  end

  # Whether this event, then, ticks it.
  def ticks_on?(event, almanac = campaign.almanac, day = campaign.day, period = campaign.period)
    triggers.include?(event.to_s) && almanac.on?(times, day, period)
  end

  # What ticks it by itself next, if anything does: "rest", "journey" or
  # "new day", for the dashed box on its dial (campaigns/clocks/_dial).
  def next_tick
    return if full? || stopped?

    { "rest" => "rest", "travel" => "journey", "dawn" => "new day" }.find { |event, _| ticks_on?(event) }&.last
  end

  # "each new day, on Monday or Friday": what ticks it, for the pages.
  def ticking
    return if triggers.empty?

    "#{triggers.map { |t| TRIGGERS[t] }.to_sentence}#{", on #{times.to_sentence(two_words_connector: ' or ', last_word_connector: ' or ')}" if times.any?}"
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
      was = filled
      update!(filled: now, full_at: now == segments ? (full_at || Time.current) : nil)
      tell_the_portents!(was) if by.positive?
      if full? && !was_full
        fill!
      elsif public? && by.positive?
        campaign.narrate("#{name}: #{filled} of #{segments}#{" (#{reason})" if reason}.")
      end
    end
    self
  end

  # Its steps on the way to full, one for each segment (Portent).
  def portent_list = Portent.list(portents)

  # The step its next segment brings, if it has one written.
  def next_portent = (portent_list[filled] unless full? || stopped?)

  # The signs of the steps it has reached, the latest first: [[portent, segment]].
  def reached_portents = portent_list.first(filled).each_with_index.map { |portent, i| [ portent, i + 1 ] }.reverse

  # What stops it: "The Terminal is cleared", or, while an antagonist who
  # lives there is at large, "Kurosaki is beaten at The Drowned Line".
  def stopper
    place = map_node.location
    villain = place && campaign.npcs.at_large.where(location_id: place.id).order(:id).first
    villain ? "#{villain.name} is beaten at #{map_node.name}" : "#{map_node.name} is cleared"
  end

  # The place whose mode it sets off when it fills.
  def place = mode&.map_node

  # The mode it sets off, named for the pages.
  def mode_name = mode&.name

  private

  # The steps the segments just filled bring, for the GM: the table only
  # sees their signs (Campaign::Remarks#offer_sign!).
  def tell_the_portents!(was)
    list = portent_list
    ((was + 1)..filled).each do |segment|
      portent = list[segment - 1] or next
      campaign.narrate("#{name}, #{segment} of #{segments}: #{portent.text}", scope: "gm")
    end
  end

  def fill!
    line = full_line || ("#{name}: it has happened." if public?)
    # Full when the table heard it, so the recap finds it in that session.
    # It stops the table (the deadline card): the date, the line, and what
    # the place has become.
    card = { "date" => campaign.world.date(campaign.day), "clock" => name, "line" => line,
             "place" => (place && "#{place.name}: #{mode.name}") }.compact
    update!(full_at: campaign.narrate(line, cue: "deadline", data: card).created_at) if line
    # What filling it does to the place (Outcome "mode", as a scene's ending can).
    Outcome.of("mode", target: { "node" => place.id, "mode" => mode.key }).apply!(campaign, by: name) if mode
  end

  def place_is_the_campaigns
    errors.add(:map_node, "isn't on this campaign's map") if map_node && map_node.campaign_id != campaign_id
  end

  def times_in_the_calendar
    unknown = campaign && campaign.almanac.unknown(times)
    errors.add(:times, "#{unknown.to_sentence} #{unknown.one? ? "isn't" : "aren't"} in the calendar") if unknown.present?
  end

  def triggers_known
    unknown = triggers - TRIGGERS.keys
    errors.add(:triggers, "aren't known: #{unknown.join(', ')}") if unknown.any?
  end

  def mode_is_the_locations
    errors.add(:mode, "isn't in this campaign") if mode && place.campaign_id != campaign_id
  end

  # The GM's list everywhere it's open, and the players' view of the public
  # clocks (on their own stream, so a hidden clock never reaches them).
  def broadcast
    campaign.table_changed
    broadcast_replace_to campaign, :gm, target: "gm_clocks", partial: "campaigns/clocks/gm", locals: { campaign: campaign }
  end
end
