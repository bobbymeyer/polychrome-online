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
    "families" => %w[text],
    "hooks" => %w[text],
    # Townsfolk couplets (Generators::Town#couplets).
    "memories" => %w[text],
    "wishes" => %w[text item],
    "service_names" => %w[text service],
    "buildings" => %w[text service width height roof],
    "stock" => %w[item],
    "rooms" => %w[text],
    "room_events" => %w[text],
    "forks" => %w[text],
    "locks" => %w[text key],
    "treasure" => %w[item gil],
    # The world's lore (Generators::Lore): what its histories and provenance are made of.
    "trades" => %w[text makes],
    "pasts" => %w[text rooms heart keeps named],
    "falls" => %w[text did sealed trace dead town],
    "quarrels" => %w[text],
    "betrayals" => %w[text],
    "fortunes" => %w[text],
    "waters" => %w[text],
    "owners" => %w[text],
    "sightings" => %w[text],
    "raids" => %w[text]
  }.freeze
  LORE_KINDS = Generators::Lore::KINDS
  # Fields that are lists, written with commas.
  LIST_FIELDS = %w[makes rooms keeps named].freeze
  INTEGER_FIELDS = %w[weight width height gil].freeze
  # What each generator draws on.
  TOWN_KINDS = %w[town_names names hooks service_names buildings stock].freeze
  # A town draws on these too, but does without them (no couplets).
  COUPLET_KINDS = %w[memories wishes].freeze
  DUNGEON_KINDS = %w[dungeon_names rooms room_events forks treasure].freeze

  # What a line of "Add many at once" holds, per kind; buildings are too
  # fiddly to paste. Any line can end in "| 3" for a weight.
  PASTE_FORMATS = {
    "town_names" => "a town's name", "dungeon_names" => "a dungeon's name", "names" => "a name",
    "families" => "a family's name (Vell)", "hooks" => "a hook",
    "memories" => "a townsperson's memory, in their own words (I lost my brother on the road to {place}.)",
    "wishes" => "a townsperson's wish, in their own words, then | and an item's name if it's a thing the party could bring them " \
                "({dungeon} names the nearest dungeon: clearing it is what they wish for)",
    "rooms" => "a room's name", "room_events" => "what happens there",
    "forks" => "what the costly way costs, then in brackets what it takes, if the game takes it (A sealed door. (pay 100); Poison gas. (hurt 10); A long climb. (2); Loose rock. (ambush))", "locks" => "the lock, then | and its key (Portal | Blue crystal)",
    "service_names" => "a name, then | and the service (inn, shop, guild or temple)",
    "stock" => "an item's name", "treasure" => "an item's name, or an amount like 150 gil",
    "trades" => "a trade, then | and what it makes, with commas (smith | blade, helm; nothing, for a trade that makes nothing to remember)",
    "pasts" => "what a dungeon was | its rooms, with commas | its heart (the boss's room) | what it kept, with commas | " \
               "words in a name that give it away, with commas (station | Ticket Hall, Platform 2 | The Last Platform | ticket, lamp | station, line)",
    "falls" => "how a place fell | what it did | how it was left | what's still there | who died there | " \
               "and, if it can strike a town too, what happened, with %s for the town (fire | burned | sealed after the fire | " \
               "Scorched beams. | who burned with it | A fire took half of %s)",
    "quarrels" => "what families fall out over (a horse sold lame)", "betrayals" => "what one family did to another (informed on them to the tax-men)",
    "fortunes" => "what goes well for a family (a good harvest)", "waters" => "somewhere to drown, when the map has no water of its own (the millpond)",
    "owners" => "how a thing changed hands, with %s for the family (Pawned by a %s, who never came back for it)",
    "sightings" => "what people say when someone who got away turns up, with {who} and {where} ({who} was seen in {where}.)",
    "raids" => "what people say when a road is raided overnight, with {from} and {to} (A caravan on the road between {from} and {to} was attacked.)"
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
      entry = row.slice("text", "key", "service", "item", "roof", *lore_fields, *INTEGER_FIELDS).transform_values(&:presence).compact
      next if entry.slice("text", "item", "gil").empty?

      INTEGER_FIELDS.each { |f| entry[f] = JsonCasting.integer(entry[f]) if entry.key?(f) }
      entry
    end)
  end

  # The lore kinds' own fields.
  def lore_fields = LORE_KINDS.flat_map { |kind| KINDS.fetch(kind) }.uniq - %w[text]

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
      when "wishes"
        wanted = parts.second.presence && items.find { |it| [ it.slug, it.name.downcase ].include?(parts.second.downcase) }
        (@paste_errors ||= []) << "line #{i + 1}: nothing in the Armory is called #{parts.second}" if parts.second.present? && !wanted
        row.merge("text" => value, "item" => wanted&.slug).compact
      when *LORE_KINDS then row.merge(fields.zip(parts).to_h { |field, part| [ field, part.to_s.presence ] }.compact)
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
      errors.add(:entries, "#{label} needs an item#{' or gil' if fields.include?('gil')}") if %w[stock treasure].include?(kind) && entry.slice("item", "gil").empty?
      errors.add(:entries, "#{label}: unknown service #{entry['service']}") if entry["service"] && !Generators::Town::SERVICES.include?(entry["service"])
      errors.add(:entries, "#{label}: unknown roof #{entry['roof']}") if entry["roof"] && !Generators::Town::ROOFS.include?(entry["roof"])
      Toll.read(entry["text"]).last.each { |problem| errors.add(:entries, "#{label}: #{problem}") } if kind == "forks"
      (INTEGER_FIELDS & entry.keys).each do |f|
        errors.add(:entries, "#{label}: #{f} must be a positive whole number") unless JsonCasting.integer?(entry[f]) && entry[f].positive?
      end
    end
  end
end
