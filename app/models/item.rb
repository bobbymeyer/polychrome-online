# frozen_string_literal: true

# Armory entry. Equipment adds flat stats (Stats::Derivation's equipment
# input); consumables carry an effect list in the same closed primitive
# vocabulary as abilities.
class Item < ApplicationRecord
  include BookEntry

  # Category -> equipment slot. Jobs grant equip permission by category.
  CATEGORIES = {
    "consumable" => nil,
    "knife" => "weapon", "sword" => "weapon", "axe" => "weapon", "spear" => "weapon",
    "staff" => "weapon", "rod" => "weapon", "bow" => "weapon",
    "shield" => "shield",
    "helmet" => "head", "hat" => "head",
    "heavy_armor" => "body", "light_armor" => "body", "robe" => "body",
    "accessory" => "accessory",
    # Oda's rare treasure (Battle::Masks): worn as an accessory, by anyone.
    "mask" => "accessory"
  }.freeze
  EQUIPMENT_CATEGORIES = (CATEGORIES.keys - [ "consumable" ]).freeze

  normalizes :target, with: ->(value) { value.presence }

  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :stats_are_stats
  validate :consumable_has_usable_effects
  validate :mask_is_a_mask

  scope :masks, -> { where(category: "mask") }

  def mask?
    category == "mask"
  end

  # A mask's own: { "type", "duration" (turns), "abilities" (slugs, its moves while worn) }.
  def mask=(value)
    value = value.to_h.stringify_keys
    super({ "type" => value["type"].presence, "duration" => JsonCasting.integer(value["duration"]),
            "abilities" => Array(value["abilities"]).compact_blank.map(&:to_s) }.compact.reject { |_, v| v == [] })
  end

  # The command a mask gives whoever wears it: put it on.
  def don_slug = "don_#{slug}"

  def don_ability
    { "name" => "Don #{name}", "kind" => "skill", "target" => "self", "cost" => { "mp" => 0 }, "gesture" => "flash",
      "effects" => [ { "primitive" => "transform", "mask" => slug } ] }
  end

  # The engine's mask (Battle::Masks).
  def to_mask
    { "name" => name, "type" => mask["type"], "duration" => mask["duration"], "abilities" => Array(mask["abilities"]),
      "image" => { "book" => "items", "slug" => slug } }.compact
  end

  def consumable?
    category == "consumable"
  end

  def equipment?
    !consumable?
  end

  def slot
    CATEGORIES[category]
  end

  def stats=(values)
    super((values || {}).to_h.stringify_keys.transform_values { |v| JsonCasting.integer(v) }.compact.reject { |_, v| v == 0 })
  end

  def effects=(rows)
    super(Ability.normalize_effects(rows))
  end

  # The engine's view of a consumable the party carries (Battle::State.build items:).
  def to_engine(count)
    { "name" => name, "target" => target, "effects" => effects, "count" => count }
  end

  # Selling back fetches half the price.
  def resale_price
    price / 2
  end

  # Stats::Derivation equipment piece.
  def to_equipment
    { "stats" => stats }
  end

  # Cross-references. Books are small, so these filter in Ruby rather than
  # query inside JSON.
  def dropped_by
    world.monsters.alphabetical.select { |monster| monster.drops.any? { |drop| drop["item"] == slug } }
  end

  def equippable_by
    world.jobs.alphabetical.select { |job| job.equips?(self) }
  end

  private

  def stats_are_stats
    unknown = stats.keys - Stats::NAMES
    errors.add(:stats, "has unknown stats: #{unknown.join(', ')}") if unknown.any?
    bad = stats.reject { |_, v| JsonCasting.integer?(v) }
    errors.add(:stats, "must be whole numbers (#{bad.keys.join(', ')})") if bad.any?
    errors.add(:stats, "only apply to equipment") if consumable? && stats.any?
  end

  def mask_is_a_mask
    if !mask?
      errors.add(:mask, "only applies to masks") if mask.present?
      return
    end
    errors.add(:mask, "type is not one of this world's types") if mask["type"] && !world_types.include?(mask["type"])
    duration = mask.fetch("duration", Battle::Masks::DEFAULT_DURATION)
    errors.add(:mask, "lasts 1 to #{Battle::Masks::MAX_DURATION} turns") unless duration.is_a?(Integer) && duration.between?(1, Battle::Masks::MAX_DURATION)
    missing = Array(mask["abilities"]) - Array(world&.abilities&.in_battle&.pluck(:slug))
    errors.add(:mask, "grants moves that aren't in the Grimoire: #{missing.join(', ')}") if missing.any?
  end

  def consumable_has_usable_effects
    if equipment?
      errors.add(:effects, "only apply to consumables") if effects.any?
      errors.add(:target, "only applies to consumables") if target.present?
      return
    end

    Battle::State.validate_ability!({ "id" => slug, "kind" => "skill", "target" => target, "effects" => effects }, world_types)
  rescue ArgumentError => e
    errors.add(:effects, e.message.delete_prefix("#{slug}: "))
  end
end
