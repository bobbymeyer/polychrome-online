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
    "accessory" => "accessory"
  }.freeze
  EQUIPMENT_CATEGORIES = (CATEGORIES.keys - [ "consumable" ]).freeze

  normalizes :target, with: ->(value) { value.presence }

  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :stats_are_stats
  validate :consumable_has_usable_effects

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
    super((values || {}).to_h.stringify_keys.transform_values { |v| JsonbCasting.integer(v) }.compact.reject { |_, v| v == 0 })
  end

  def effects=(rows)
    super(Ability.normalize_effects(rows))
  end

  # Stats::Derivation equipment piece.
  def to_equipment
    { "stats" => stats }
  end

  def dropped_by
    world.monsters.where("drops @> ?", [ { item: slug } ].to_json).alphabetical
  end

  def equippable_by
    world.jobs.where("equip_categories ? :category", category: category).alphabetical
  end

  private

  def stats_are_stats
    unknown = stats.keys - Stats::NAMES
    errors.add(:stats, "has unknown stats: #{unknown.join(', ')}") if unknown.any?
    bad = stats.reject { |_, v| JsonbCasting.integer?(v) }
    errors.add(:stats, "must be whole numbers (#{bad.keys.join(', ')})") if bad.any?
    errors.add(:stats, "only apply to equipment") if consumable? && stats.any?
  end

  def consumable_has_usable_effects
    if equipment?
      errors.add(:effects, "only apply to consumables") if effects.any?
      errors.add(:target, "only applies to consumables") if target.present?
      return
    end

    Battle::State.validate_ability!("id" => slug, "kind" => "skill", "target" => target, "effects" => effects)
  rescue ArgumentError => e
    errors.add(:effects, e.message.delete_prefix("#{slug}: "))
  end
end
