# frozen_string_literal: true

# Grimoire entry: one of the engine's closed primitives, composed (§3.1).
# `effects` is stored in exactly the shape Battle::Resolver reads.
class Ability < ApplicationRecord
  include BookEntry
  include Artwork

  KINDS = %w[skill magic].freeze
  # Motion gestures (§3.2): the view's hint for how the caster moves.
  GESTURES = %w[bounce shake flash fade spin lunge pop float tint slide].freeze

  has_many :job_levels, dependent: :restrict_with_error
  has_many :jobs, -> { distinct }, through: :job_levels

  normalizes :gesture, with: ->(value) { value.presence }

  validates :kind, inclusion: { in: KINDS }
  validates :target, inclusion: { in: Battle::TARGETINGS }
  validates :mp_cost, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :gesture, inclusion: { in: GESTURES }, allow_blank: true
  validates :slug, exclusion: { in: %w[attack], message: "is reserved for the built-in Attack" }
  validate :engine_accepts_effects

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
      "cost" => { "mp" => mp_cost.to_i },
      "effects" => effects,
      "gesture" => gesture.presence
    }.compact
  end

  # Cross-references (§7: "cross-references between entries are the index").
  # Books are small, so these filter in Ruby rather than query inside JSON.
  def monsters_using
    world.monsters.alphabetical.select { |monster| monster.ability_slugs.include?(slug) }
  end

  private

  def engine_accepts_effects
    Battle::State.validate_ability!(to_engine.merge("id" => slug), world_types)
  rescue ArgumentError => e
    errors.add(:effects, e.message.delete_prefix("#{slug}: "))
  end
end
