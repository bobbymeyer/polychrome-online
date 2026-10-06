# frozen_string_literal: true

# One of a place's other states (MapNode::Modes): prepared by the GM and
# set off at the table. The city burns, the mine floods, the festival
# starts. While it lasts, some services are shut, the music changes, there
# can be trouble on arrival, and players read a line about it. Clocks,
# scenes and its picture point at it. A mode with times comes on by itself
# when the calendar says (Pointcrawl::Calendar#on?) and goes when it
# doesn't: the place by night, in winter, on market day. It can have things
# to do of its own (activities, written as a place's are: Pastime), and
# shut the place's usual ones ("pastimes" in closed).
class Mode < ApplicationRecord
  belongs_to :map_node, touch: true
  belongs_to :encounter_table, optional: true
  has_one :mode_art, dependent: :destroy
  has_many :clocks, dependent: :nullify
  has_many :scenes, dependent: :nullify

  normalizes :name, with: ->(name) { name.to_s.strip }
  normalizes :line, :description, :activities, with: ->(text) { text.to_s.strip.presence }
  normalizes :music, with: ->(music) { music.presence }

  before_validation { self.key = name.parameterize(separator: "_") if key.blank? && name.present? }

  validates :name, presence: true
  validates :key, presence: true, uniqueness: { scope: :map_node_id }
  validates :music, inclusion: { in: Campaign::MUSIC_CHOICES }, allow_nil: true
  validate :trouble_from_this_world
  validate :times_in_the_calendar, if: :will_save_change_to_times?
  validate { Pastime.parse(activities, almanac).last.each { |problem| errors.add(:activities, problem) } if map_node }

  def closed=(kinds)
    super(Array(kinds).compact_blank.map(&:to_s))
  end

  def shuts?(kind) = closed.include?(kind.to_s)

  # When it comes on by itself, in the calendar's words: parts of the
  # day, days of the week, months, seasons ("winter", "night": winter nights).
  def times=(words)
    super(Array(words).map { |word| word.to_s.strip }.reject(&:empty?).uniq(&:downcase))
  end

  # It follows the calendar (MapNode#follow_the_hours!) instead of being set off.
  def timed? = times.any?

  def almanac = map_node.campaign.world.almanac

  # The town or dungeon there, if any (its picture, its page).
  def location = map_node&.location

  private

  def times_in_the_calendar
    return unless map_node

    unknown = almanac.unknown(times)
    errors.add(:times, "#{unknown.to_sentence} #{unknown.one? ? "isn't" : "aren't"} in #{map_node.campaign.world.name}'s calendar") if unknown.any?
  end

  def trouble_from_this_world
    return unless encounter_table && map_node

    errors.add(:encounter_table, "isn't one of #{map_node.campaign.world.name}'s") unless encounter_table.world_id == map_node.campaign.world_id
  end
end
