# frozen_string_literal: true

# Generator Tables book entry (§4): the raw material towns and dungeons are
# rolled from. Each table has one kind; its entries are weighted rows whose
# fields depend on the kind. Raw material, so no art of its own.
class GeneratorTable < ApplicationRecord
  include BookEntry

  # kind => the fields its entries use (besides "weight").
  KINDS = {
    "town_names" => %w[text],
    "dungeon_names" => %w[text],
    "names" => %w[text],
    "hooks" => %w[text],
    "service_names" => %w[text service],
    "buildings" => %w[text service width height roof],
    "stock" => %w[item],
    "rooms" => %w[text],
    "room_events" => %w[text],
    "forks" => %w[text],
    "locks" => %w[text key],
    "treasure" => %w[item gil]
  }.freeze
  INTEGER_FIELDS = %w[weight width height gil].freeze
  # What each generator draws on.
  TOWN_KINDS = %w[town_names names hooks service_names buildings stock].freeze
  DUNGEON_KINDS = %w[dungeon_names rooms room_events forks treasure].freeze

  # What a line of "Add many at once" holds, per kind; buildings are too
  # fiddly to paste. Any line can end in "| 3" for a weight.
  PASTE_FORMATS = {
    "town_names" => "a town's name", "dungeon_names" => "a dungeon's name", "names" => "a name",
    "hooks" => "a hook", "rooms" => "a room's name", "room_events" => "what happens there",
    "forks" => "what the costly way costs", "locks" => "the lock, then | and its key (Portal | Blue crystal)",
    "service_names" => "a name, then | and the service (inn, shop, guild or temple)",
    "stock" => "an item's name", "treasure" => "an item's name, or an amount like 150 gil"
  }.freeze

  attr_accessor :paste

  validates :kind, inclusion: { in: KINDS.keys }
  before_validation :keep_the_kinds_fields, :add_pasted_rows
  validate :entries_fit_the_kind

  scope :of_kind, ->(kind) { where(kind: kind) }

  def fields
    KINDS.fetch(kind, [])
  end

  # Form rows or plain hashes; blank rows are dropped, numbers cast.
  def entries=(rows)
    super(JsonCasting.rows(rows).filter_map do |row|
      entry = row.slice("text", "key", "service", "item", "roof", *INTEGER_FIELDS).transform_values(&:presence).compact
      next if entry.slice("text", "item", "gil").empty?

      INTEGER_FIELDS.each { |f| entry[f] = JsonCasting.integer(entry[f]) if entry.key?(f) }
      entry
    end)
  end

  private

  # One row per non-blank pasted line, after the rows already in the form.
  def add_pasted_rows
    lines = paste.to_s.lines.map(&:strip).reject(&:empty?)
    return if lines.empty? || !PASTE_FORMATS.key?(kind)

    items = world.items.to_a
    rows = lines.each_with_index.filter_map do |line, i|
      parts = line.split("|").map(&:strip)
      row = parts.size > 1 && parts.last.match?(/\A\d+\z/) ? { "weight" => parts.pop.to_i } : {}
      value = parts.first.to_s
      case kind
      when "stock", "treasure"
        if kind == "treasure" && (gil = value[/\A(\d+)\s*gil\z/i, 1])
          row.merge("gil" => gil.to_i)
        elsif (item = items.find { |it| [ it.slug, it.name.downcase ].include?(value.downcase) })
          row.merge("item" => item.slug)
        else
          (@paste_errors ||= []) << "line #{i + 1}: nothing in the Armory is called #{value}"
          nil
        end
      when "service_names" then row.merge("text" => value, "service" => parts.second.to_s.downcase.presence).compact
      when "locks" then row.merge("text" => value, "key" => parts.second.presence).compact
      else row.merge("text" => value)
      end
    end
    return if @paste_errors.present? # nothing added until every line reads

    self.entries = entries + rows
    self.paste = nil
  end

  # A form hides the columns its kind doesn't use; if the kind changed,
  # whatever those columns held goes.
  def keep_the_kinds_fields
    return unless KINDS.key?(kind)

    kept = entries.map { |entry| entry.slice(*fields, "weight") }.reject { |entry| entry.slice("text", "item", "gil").empty? }
    self.entries = kept if kept != entries
  end

  def entries_fit_the_kind
    @paste_errors&.each { |message| errors.add(:paste, message) }
    errors.add(:entries, "need at least one row") if entries.empty?
    items = world ? world.items.pluck(:slug) : []
    entries.each_with_index do |entry, i|
      label = "row #{i + 1}"
      extra = entry.keys - fields - [ "weight" ]
      errors.add(:entries, "#{label} has fields a #{kind.to_s.humanize.downcase} table doesn't use: #{extra.join(', ')}") if extra.any?
      errors.add(:entries, "#{label} needs text") if fields.include?("text") && entry["text"].blank?
      errors.add(:entries, "#{label} needs a key") if fields.include?("key") && entry["key"].blank?
      errors.add(:entries, "#{label}: #{entry['item']} is not in the Armory") if entry["item"] && !items.include?(entry["item"])
      errors.add(:entries, "#{label} needs an item#{' or gil' if fields.include?('gil')}") if fields.include?("item") && entry.slice("item", "gil").empty?
      errors.add(:entries, "#{label}: unknown service #{entry['service']}") if entry["service"] && !Generators::Town::SERVICES.include?(entry["service"])
      errors.add(:entries, "#{label}: unknown roof #{entry['roof']}") if entry["roof"] && !Generators::Town::ROOFS.include?(entry["roof"])
      (INTEGER_FIELDS & entry.keys).each do |f|
        errors.add(:entries, "#{label}: #{f} must be a positive whole number") unless JsonCasting.integer?(entry[f]) && entry[f].positive?
      end
    end
  end
end
