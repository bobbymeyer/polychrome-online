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

  # Points added to a check with a skill the job is good at (Stats::Check).
  SKILL_BONUS = 15

  # What time spent on things to do pays someone in the job, at the next
  # rest (Campaign::Payoffs): money for the party, EXP or ABP for them, per
  # part of the day; or a rumour, once.
  PAYOFFS = %w[money exp abp rumour].freeze

  validates :ability_slots, numericality: { only_integer: true, in: 0..4 }
  validate :skills_are_the_worlds
  validate :multipliers_are_percentages
  validate :equip_categories_exist
  validate :innates_are_passives
  validate :desperation_is_an_attack
  validate :signature_is_an_ability
  validate :field_ability_is_a_field_ability
  validates :passive, inclusion: { in: Battle::PASSIVES }, allow_nil: true
  validate :payoff_is_a_payoff
  # A character in the job has its type: hit as the chart says, and hitting
  # with it through Attack and the job's own command.
  before_validation :default_to_plain_type, on: :create
  validates :base_type, inclusion: { in: ->(job) { job.world_types }, message: "isn't one of this world's types" }

  normalizes :desperation, :signature, :passive, :field_ability, with: ->(slug) { slug.presence }

  # The job's move outside battle (FieldUse): a Grimoire entry of kind field.
  def field_ability_entry
    field_ability && world.abilities.field.find_by(slug: field_ability)
  end

  # The job's own command: always on the menu while in the job, learned or not.
  def signature_ability
    signature && world.abilities.find_by(slug: signature)
  end

  # The move an attack can become at the end of a character's rope, once a
  # battle (Battle::Resolver#desperate). Any offensive Grimoire entry.
  def desperation_ability
    desperation && world.abilities.find_by(slug: desperation)
  end

  # Percent per stat (120 = x1.2). Blank or 100 means unmodified.
  def stat_multipliers=(values)
    super((values || {}).to_h.stringify_keys.transform_values { |v| JsonCasting.integer(v) }.compact.reject { |_, v| v == 100 })
  end

  # Slugs of the world's skills (World#skills) the job is good at.
  def skills=(values)
    super(Array(values).map(&:to_s).compact_blank.uniq)
  end

  def skill_names
    skills.map { |slug| world.skill_name(slug) }
  end

  # { "kind" => one of PAYOFFS, "amount" => per part of the day, "line" =>
  # "{who} works the counter: {amount}." }. No kind: no payoff.
  def payoff=(value)
    value = value.to_h.stringify_keys
    kind = value["kind"].to_s.strip
    super(kind.empty? ? {} : { "kind" => kind, "amount" => value["amount"].to_i, "line" => value["line"].to_s.strip.presence }.compact)
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

  # What a job's type gives a character in it, in battle (Battle::State).
  # Attack and the signature strike with the job's type when the author
  # says so (typed_attack), and never for a job of the world's plain type:
  # a mage's staff is only a staff, and shouldn't do nothing to half of
  # what it meets, but that's the author's call, not a reading of the stats.
  def battle_type
    { "types" => [ base_type ], "attack_type" => (base_type unless typeless_attack?), "immune_as_resist" => true }.compact
  end

  def typeless_attack?
    base_type == world.type_chart.plain || !typed_attack?
  end

  private

  def payoff_is_a_payoff
    return if payoff.blank?

    errors.add(:payoff, "must be one of #{PAYOFFS.join(', ')}") unless PAYOFFS.include?(payoff["kind"])
    errors.add(:payoff, "needs an amount from 1 to 9999") unless payoff["kind"] == "rumour" || payoff["amount"].to_i.between?(1, 9999)
  end

  def multipliers_are_percentages
    unknown = stat_multipliers.keys - Stats::NAMES
    errors.add(:stat_multipliers, "has unknown stats: #{unknown.join(', ')}") if unknown.any?
    bad = stat_multipliers.reject { |_, v| JsonCasting.integer?(v) && v.between?(0, 500) }
    errors.add(:stat_multipliers, "must be whole percents from 0 to 500 (#{bad.keys.join(', ')})") if bad.any?
  end

  def skills_are_the_worlds
    unknown = skills - Array(world&.skills).map { |s| s["slug"] }
    errors.add(:skills, "aren't this world's: #{unknown.join(', ')}") if unknown.any?
  end

  def equip_categories_exist
    unknown = equip_categories - Item::EQUIPMENT_CATEGORIES
    errors.add(:equip_categories, "has unknown categories: #{unknown.join(', ')}") if unknown.any?
  end

  def field_ability_is_a_field_ability
    errors.add(:field_ability, "must be a field ability in the Grimoire") if field_ability && !world&.abilities&.field&.exists?(slug: field_ability)
  end

  def signature_is_an_ability
    errors.add(:signature, "must be an ability in the Grimoire") if signature && !world&.abilities&.exists?(slug: signature)
  end

  def desperation_is_an_attack
    return unless desperation

    ability = world&.abilities&.find_by(slug: desperation)
    if ability.nil?
      errors.add(:desperation, "must be an ability in the Grimoire")
    elsif !%w[single_enemy all_enemies random_enemy].include?(ability.target)
      errors.add(:desperation, "must be aimed at enemies")
    end
  end

  def innates_are_passives
    innates.each do |passive|
      errors.add(:innates, "#{passive['stat']} is not a stat") unless Stats::NAMES.include?(passive["stat"])
      values = passive.slice("add", "percent").values
      errors.add(:innates, "#{passive['stat']} needs a whole-number add or percent") if values.empty? || !values.all? { |v| JsonCasting.integer?(v) }
    end
  end
end
