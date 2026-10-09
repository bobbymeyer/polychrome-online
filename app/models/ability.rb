# frozen_string_literal: true

# Grimoire entry: one of the engine's closed primitives, composed (§3.1).
# `effects` is stored in exactly the shape Battle::Resolver reads.
class Ability < ApplicationRecord
  include BookEntry

  # field: a move outside battle (FieldUse), a skill check with an outcome;
  # never in battle.
  KINDS = %w[skill magic field].freeze
  # Motion gestures (§3.2): the view's hint for how the caster moves.
  GESTURES = %w[bounce shake flash fade spin lunge pop float tint slide].freeze

  has_many :job_levels, dependent: :restrict_with_error
  has_many :jobs, -> { distinct }, through: :job_levels
  # A monster's script that uses it would break every battle it's in (Battle::State.build).
  before_destroy :not_in_a_script

  normalizes :gesture, with: ->(value) { value.presence }
  # A field ability aims at no one in battle; the column wants something.
  before_validation { self.target = "self" if field? && target.blank? }

  validates :kind, inclusion: { in: KINDS }
  validates :target, inclusion: { in: Battle::TARGETINGS }, unless: :field?
  validates :field_outcome, inclusion: { in: FieldUse::OUTCOMES.keys }, if: :field?
  validates :field_difficulty, inclusion: { in: Stats::Check::DIFFICULTIES.keys }
  validates :field_power, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :field_skill_is_the_worlds, if: :field?
  validate :summons_are_in_the_bestiary
  validates :mp_cost, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :hp_cost, numericality: { only_integer: true, in: 0..Battle::MAX_HP_COST }
  validates :charge, numericality: { only_integer: true, in: 0..Battle::MAX_CHARGE }
  # reload: turns the user is spent for after it. reach: it finds what's off
  # the field (a Ranger's shot).
  validates :reload_turns, numericality: { only_integer: true, in: 0..Battle::MAX_RELOAD }
  validates :gesture, inclusion: { in: GESTURES }, allow_blank: true
  validates :slug, exclusion: { in: %w[attack], message: "is reserved for the built-in Attack" }
  validate :engine_accepts_effects

  def field?
    kind == "field"
  end

  scope :in_battle, -> { where.not(kind: "field") }
  scope :field, -> { where(kind: "field") }

  def effects=(rows)
    super(self.class.normalize_effects(rows))
  end

  # Accepts form rows or engine-shaped effect hashes. Rows without a
  # primitive are dropped; params the primitive doesn't take are dropped;
  # numbers are cast. Anything else is left for validation to report.
  # Shared with Item (consumables).
  def self.normalize_effects(rows)
    JsonCasting.rows(rows).filter_map do |row|
      primitive = row["primitive"].presence or next
      spec = Battle::PRIMITIVE_PARAMS[primitive]
      next { "primitive" => primitive } unless spec

      params = (spec[:required] + spec[:optional]).filter_map do |param|
        value = row[param]
        next if value.blank?

        [ param, Battle::PRIMITIVE_STRING_PARAMS.include?(param) ? value.to_s : JsonCasting.integer(value) ]
      end
      { "primitive" => primitive }.merge(params.to_h)
    end
  end

  def to_engine
    {
      "name" => name,
      "kind" => kind,
      "target" => target,
      "cost" => { "mp" => mp_cost.to_i, "hp" => (hp_cost if hp_cost.to_i.positive?) }.compact,
      "effects" => effects,
      "gesture" => gesture.presence,
      "charge" => (charge if charge.to_i.positive?),
      "reload" => (reload_turns if reload_turns.to_i.positive?),
      "reach" => (true if reach?)
    }.compact
  end

  # Cross-references (§7: "cross-references between entries are the index").
  # Books are small, so these filter in Ruby rather than query inside JSON.
  def monsters_using
    world.monsters.alphabetical.select { |monster| monster.ability_slugs.include?(slug) }
  end

  private

  def not_in_a_script
    return if destroyed_by_association # the whole world is going, books and all

    users = monsters_using
    return if users.empty?

    errors.add(:base, "#{name} is still used by #{users.map(&:name).to_sentence}. Change their scripts first.")
    throw :abort
  end

  def summons_are_in_the_bestiary
    creatures = Array(effects).filter_map { |e| e["creature"] if e["primitive"] == "summon" }
    missing = creatures - Array(world&.monsters&.where(slug: creatures)&.pluck(:slug))
    errors.add(:effects, "summon #{missing.join(', ')}, who aren't in the Bestiary") if missing.any?
  end

  def field_skill_is_the_worlds
    errors.add(:field_skill, "must be one of #{world&.name}'s skills") unless world&.skill(field_skill)
  end

  def engine_accepts_effects
    return if field?

    Battle::State.validate_ability!(to_engine.merge("id" => slug), world_types)
  rescue ArgumentError => e
    errors.add(:effects, e.message.delete_prefix("#{slug}: "))
  end
end
