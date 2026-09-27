# frozen_string_literal: true

# Job Compendium entry, FF5-style: stat multipliers, equip permissions by
# item category, innate passives, and a learn table of job levels.
class Job < ApplicationRecord
  include BookEntry
  include Artwork
  include Colourable

  has_many :job_levels, -> { order(:level) }, dependent: :destroy, inverse_of: :job
  has_many :abilities, through: :job_levels

  accepts_nested_attributes_for :job_levels, allow_destroy: true,
                                             reject_if: ->(attrs) { attrs["id"].blank? && attrs["ability_id"].blank? }

  validates :ability_slots, numericality: { only_integer: true, in: 0..4 }
  validate :multipliers_are_percentages
  validate :equip_categories_exist
  validate :innates_are_passives

  # Percent per stat (120 = x1.2). Blank or 100 means unmodified.
  def stat_multipliers=(values)
    super((values || {}).to_h.stringify_keys.transform_values { |v| JsonCasting.integer(v) }.compact.reject { |_, v| v == 100 })
  end

  def equip_categories=(values)
    super(Array(values).map(&:to_s).compact_blank.uniq)
  end

  # Rows of { stat, add, percent } — the Stats::Derivation passive shape.
  def innates=(rows)
    super(JsonCasting.rows(rows).filter_map do |row|
      next if row["stat"].blank?

      { "stat" => row["stat"].to_s, "add" => JsonCasting.integer(row["add"]),
        "percent" => JsonCasting.integer(row["percent"]) }.compact
    end)
  end

  def equips?(item)
    equip_categories.include?(item.category)
  end

  # Stats::Derivation inputs.
  def to_derivation
    { "multipliers" => stat_multipliers }
  end

  def passives
    innates
  end

  def total_abp
    job_levels.sum(&:abp)
  end

  private

  def multipliers_are_percentages
    unknown = stat_multipliers.keys - Stats::NAMES
    errors.add(:stat_multipliers, "has unknown stats: #{unknown.join(', ')}") if unknown.any?
    bad = stat_multipliers.reject { |_, v| JsonCasting.integer?(v) && v.between?(0, 500) }
    errors.add(:stat_multipliers, "must be whole percents from 0 to 500 (#{bad.keys.join(', ')})") if bad.any?
  end

  def equip_categories_exist
    unknown = equip_categories - Item::EQUIPMENT_CATEGORIES
    errors.add(:equip_categories, "has unknown categories: #{unknown.join(', ')}") if unknown.any?
  end

  def innates_are_passives
    innates.each do |passive|
      errors.add(:innates, "#{passive['stat']} is not a stat") unless Stats::NAMES.include?(passive["stat"])
      values = passive.slice("add", "percent").values
      errors.add(:innates, "#{passive['stat']} needs a whole-number add or percent") if values.empty? || !values.all? { |v| JsonCasting.integer?(v) }
    end
  end
end
