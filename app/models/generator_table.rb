# frozen_string_literal: true

# Generator Tables book entry (§4): the raw material towns and dungeons are
# rolled from. Each table has one kind; its entries are weighted rows whose
# fields depend on the kind.
class GeneratorTable < ApplicationRecord
  include BookEntry

  # kind => the fields its entries use (besides "weight").
  KINDS = {
    "place_names" => %w[text],
    "names" => %w[text],
    "hooks" => %w[text],
    "service_names" => %w[text service],
    "buildings" => %w[text service width height roof],
    "stock" => %w[item],
    "rooms" => %w[text],
    "room_events" => %w[text],
    "forks" => %w[text],
    "treasure" => %w[item]
  }.freeze
  INTEGER_FIELDS = %w[weight width height].freeze

  validates :kind, inclusion: { in: KINDS.keys }
  validate :entries_fit_the_kind

  scope :of_kind, ->(kind) { where(kind: kind) }

  def fields
    KINDS.fetch(kind, [])
  end

  # Form rows or plain hashes; blank rows are dropped, numbers cast.
  def entries=(rows)
    super(JsonCasting.rows(rows).filter_map do |row|
      entry = row.slice("text", "service", "item", "roof", *INTEGER_FIELDS).transform_values(&:presence).compact
      next if entry.slice("text", "item").empty?

      INTEGER_FIELDS.each { |f| entry[f] = JsonCasting.integer(entry[f]) if entry.key?(f) }
      entry
    end)
  end

  private

  def entries_fit_the_kind
    errors.add(:entries, "need at least one row") if entries.empty?
    items = world ? world.items.pluck(:slug) : []
    entries.each_with_index do |entry, i|
      label = "row #{i + 1}"
      extra = entry.keys - fields - [ "weight" ]
      errors.add(:entries, "#{label} has fields a #{kind.to_s.humanize.downcase} table doesn't use: #{extra.join(', ')}") if extra.any?
      errors.add(:entries, "#{label} needs text") if fields.include?("text") && entry["text"].blank?
      errors.add(:entries, "#{label}: #{entry['item']} is not in the Armory") if fields.include?("item") && !items.include?(entry["item"])
      errors.add(:entries, "#{label}: unknown service #{entry['service']}") if entry["service"] && !Generators::Town::SERVICES.include?(entry["service"])
      errors.add(:entries, "#{label}: unknown roof #{entry['roof']}") if entry["roof"] && !Generators::Town::ROOFS.include?(entry["roof"])
      (INTEGER_FIELDS & entry.keys).each do |f|
        errors.add(:entries, "#{label}: #{f} must be a positive whole number") unless JsonCasting.integer?(entry[f]) && entry[f].positive?
      end
    end
  end
end
