# frozen_string_literal: true

# Gazetteer book entry (§2, §4): a town or dungeon archetype with the
# settings its generator uses. Campaign locations are rolled from these.
class LocationTemplate < ApplicationRecord
  include BookEntry
  include Artwork

  KINDS = %w[town dungeon].freeze
  RANGES = { "town" => %w[npcs stock buildings], "dungeon" => %w[rooms] }.freeze
  DEFAULTS = {
    "town" => { "services" => { "inn" => 100, "shop" => 80, "guild" => 40, "temple" => 40 },
                "npcs" => [ 3, 5 ], "stock" => [ 4, 6 ], "buildings" => [ 8, 12 ] },
    "dungeon" => { "rooms" => [ 6, 9 ], "loops" => 1, "locks" => 0,
                   "decisions" => { "encounter" => 4, "event" => 2, "treasure" => 2, "fork" => 1 } }
  }.freeze

  belongs_to :encounter_table, optional: true
  has_many :locations, dependent: :restrict_with_error

  validates :kind, inclusion: { in: KINDS }
  validate :config_is_sensible
  validate :encounter_table_from_this_world

  def town?
    kind == "town"
  end

  def dungeon?
    kind == "dungeon"
  end

  # Form fields arrive flat; store the generator's shape.
  def config=(values)
    values = (values || {}).to_h.stringify_keys
    int = ->(v) { JsonCasting.integer(v) }
    config = {}
    config["services"] = values["services"].to_h.transform_values(&int).compact if values["services"]
    config["decisions"] = values["decisions"].to_h.transform_values(&int).compact if values["decisions"]
    RANGES.values.flatten.each do |key|
      range = values[key]
      range = [ values["#{key}_min"], values["#{key}_max"] ] if range.nil? && (values["#{key}_min"] || values["#{key}_max"])
      config[key] = Array(range).map(&int) if range
    end
    config["loops"] = int.(values["loops"]) if values.key?("loops")
    config["locks"] = int.(values["locks"]) if values.key?("locks")
    boss = values["boss"].to_h.transform_values(&int)
    boss = { values["boss_monster"] => int.(values["boss_count"]) || 1 } if values.key?("boss_monster")
    boss = boss.reject { |slug, count| slug.blank? || count.nil? }
    config["boss"] = boss if boss.any?
    config["tables"] = Array(values["tables"]).compact_blank if values.key?("tables")
    super(config.compact)
  end

  # Settings with defaults filled in.
  def settings
    DEFAULTS.fetch(kind, {}).merge(config.except("tables"))
  end

  def generator_tables
    chosen = config.fetch("tables", [])
    chosen.any? ? world.generator_tables.where(slug: chosen) : world.generator_tables
  end

  # Kinds this template pools from more than one table (two rooms tables,
  # say): usually a slip, since every place of this kind then mixes them.
  def crowded_kinds
    generator_tables.group(:kind).count.select { |kind, n| n > 1 && %w[rooms locks dungeon_names town_names].include?(kind) }.keys
  end

  # { kind => pooled entries } for the generator. Read once per template
  # (every place made from it asks).
  def table_entries
    @table_entries = nil if @table_entries && changed?
    @table_entries ||= generator_tables.group_by(&:kind).transform_values { |tables| tables.flat_map(&:entries) }
  end

  private

  def config_is_sensible
    settings.slice(*RANGES.fetch(kind, [])).each do |key, (min, max)|
      unless [ min, max ].all? { |v| JsonCasting.integer?(v) && v.between?(0, 30) } && min <= max
        errors.add(:config, "#{key} must be a range of whole numbers, min ≤ max")
      end
    end
    settings.slice("services", "decisions").each do |key, weights|
      errors.add(:config, "#{key} must be whole numbers from 0") unless weights.values.all? { |v| JsonCasting.integer?(v) && v >= 0 }
    end
    errors.add(:config, "dungeons need at least 2 rooms") if dungeon? && settings["rooms"]&.first.to_i < 2
    errors.add(:config, "loops must be 0–5") if dungeon? && !settings["loops"].to_i.between?(0, 5)
    errors.add(:config, "locks must be 0–3") if dungeon? && !settings["locks"].to_i.between?(0, 3)
    unknown = Array(config["boss"]&.keys) - (world ? world.monsters.pluck(:slug) : [])
    errors.add(:config, "boss #{unknown.join(', ')} is not in the Bestiary") if unknown.any?
  end

  def encounter_table_from_this_world
    errors.add(:encounter_table, "must come from this world") if encounter_table && world && encounter_table.world_id != world_id
  end
end
