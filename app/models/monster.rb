# frozen_string_literal: true

# Bestiary entry: a stat block, a base type (Battle::Types) with any
# affinities that break the type chart, an FF-style AI script
# (ordered condition/action rules, §5), rewards and a drop table. The
# engine reads the entry through #to_engine; enemies in a battle are
# instances of it.
class Monster < ApplicationRecord
  include BookEntry
  include Colourable

  validates :level, numericality: { only_integer: true, greater_than: 0 }
  validates :exp, :gil, :abp, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :stat_block_is_complete
  before_validation :default_to_plain_type, on: :create
  validates :base_type, inclusion: { in: ->(monster) { monster.world_types }, message: "isn't one of this world's types" }
  validate :affinities_are_affinities
  validate :status_immunities_are_statuses
  validate :ai_script_is_valid
  validate :drops_are_items

  def stats=(values)
    super((values || {}).to_h.stringify_keys.transform_values { |v| JsonCasting.integer(v) }.compact)
  end

  # Only the exceptions are stored: blank or "normal" means the chart decides.
  def affinities=(values)
    super((values || {}).to_h.stringify_keys.transform_values(&:to_s).reject { |_, v| v.blank? || v == "normal" })
  end

  def status_immune=(values)
    super(Array(values).map(&:to_s).compact_blank.uniq)
  end

  # Accepts engine-shaped rules ({ "if" => {...}, "use", "target" }) or flat
  # form rows ({ "use", "target", "self_hp_below" => "30", ... }).
  def ai_script=(rows)
    super(JsonCasting.rows(rows).filter_map do |row|
      next if row["use"].blank?

      conditions = row.fetch("if") { row.slice(*Battle::AI::CONDITIONS) }.to_h.stringify_keys
      conditions = conditions.filter_map do |name, value|
        next if value.blank? || value == "0" && name == "ally_ko"

        [ name, name == "ally_ko" ? ActiveModel::Type::Boolean.new.cast(value) : JsonCasting.integer(value) ]
      end.to_h
      { "if" => conditions.presence, "use" => row["use"].to_s, "target" => row["target"].presence }.compact
    end)
  end

  def drops=(rows)
    super(JsonCasting.rows(rows).filter_map do |row|
      next if row["item"].blank?

      { "item" => row["item"].to_s, "chance" => JsonCasting.integer(row["chance"]) || 100 }
    end)
  end

  # Abilities the script can use, beyond the built-in Attack.
  def ability_slugs
    ai_script.map { |rule| rule["use"] }.uniq - [ "attack" ]
  end

  def abilities
    world.abilities.where(slug: ability_slugs).alphabetical
  end

  def drop_items
    world.items.where(slug: drops.map { |d| d["item"] }).index_by(&:slug)
  end

  def rewards
    { "exp" => exp, "gil" => gil, "abp" => abp }
  end

  # Enemy spec for Battle::State.build.
  def to_engine(count: 1)
    {
      "id" => slug,
      "name" => name,
      "count" => count,
      "stats" => stats,
      "types" => [ base_type ],
      "affinities" => affinities,
      "status_immune" => status_immune,
      "abilities" => ability_slugs,
      "ai" => ai_script,
      "rewards" => rewards,
      "drops" => (names = drop_items.transform_values(&:name); drops.map { |d| d.merge("name" => names[d["item"]]).compact }),
      "image" => { "book" => "monsters", "slug" => slug }
    }.merge(undead? ? { "undead" => true } : {}).merge(boss? ? { "boss" => true } : {})
  end

  private

  def stat_block_is_complete
    missing = Stats::NAMES - stats.keys
    errors.add(:stats, "is missing #{missing.join(', ')}") if missing.any?
    unknown = stats.keys - Stats::NAMES
    errors.add(:stats, "has unknown stats: #{unknown.join(', ')}") if unknown.any?
    bad = stats.reject { |name, v| JsonCasting.integer?(v) && v.between?(name == "max_hp" ? 1 : 0, Stats::CAPS.fetch(name, Float::INFINITY)) }
    errors.add(:stats, "must be whole numbers within caps (#{bad.keys.join(', ')})") if bad.any?
  end

  def affinities_are_affinities
    affinities.each do |type, affinity|
      errors.add(:affinities, "#{type} is not one of this world's types") unless world_types.include?(type)
      errors.add(:affinities, "#{affinity} is not an affinity") unless Battle::AFFINITIES.include?(affinity)
    end
  end

  def status_immunities_are_statuses
    unknown = status_immune - Battle::STATUSES
    errors.add(:status_immune, "has unknown statuses: #{unknown.join(', ')}") if unknown.any?
  end

  def ai_script_is_valid
    known = world ? world.abilities.where(slug: ability_slugs).pluck(:slug) : []
    ai_script.each_with_index do |rule, i|
      label = "rule #{i + 1}"
      use = rule["use"]
      errors.add(:ai_script, "#{label} uses #{use}, which is not in the Grimoire") unless use == "attack" || known.include?(use)
      if rule["target"] && !Battle::AI::STRATEGIES.include?(rule["target"])
        errors.add(:ai_script, "#{label} has unknown target #{rule['target']}")
      end
      rule.fetch("if", {}).each do |name, value|
        next errors.add(:ai_script, "#{label} has unknown condition #{name}") unless Battle::AI::CONDITIONS.include?(name)
        next if name == "ally_ko"

        errors.add(:ai_script, "#{label} #{name} must be a positive whole number") unless JsonCasting.integer?(value) && value.positive?
      end
    end
  end

  def drops_are_items
    known = world ? drop_items : {}
    drops.each do |drop|
      errors.add(:drops, "#{drop['item']} is not in the Armory") unless known.key?(drop["item"])
      chance = drop["chance"]
      errors.add(:drops, "#{drop['item']} chance must be 1–100") unless JsonCasting.integer?(chance) && chance.between?(1, 100)
    end
  end
end
