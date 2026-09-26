# frozen_string_literal: true

# Encounter Tables book entry (§2, §4): weighted monster groups for a
# terrain and tier. Map edges point at these; crossing an edge rolls on one
# (Pointcrawl::Encounters).
class EncounterTable < ApplicationRecord
  include BookEntry

  TERRAINS = %w[plains forest desert mountain cave crypt sea town].freeze
  MAX_GROUP = 8

  has_many :map_edges, dependent: :nullify

  validates :terrain, inclusion: { in: TERRAINS }
  validates :tier, numericality: { only_integer: true, in: 1..10 }
  validate :entries_are_monster_groups

  # Form rows: { "weight" => "3", "monster" => "goblin", "count" => "3",
  # "monster_2" => "wolf", "count_2" => "1" }. Seeds pass engine-shaped
  # { "weight", "monsters" => { slug => count } }.
  def entries=(rows)
    super(JsonCasting.rows(rows).filter_map do |row|
      monsters = row["monsters"]&.to_h&.transform_values { |count| JsonCasting.integer(count) } ||
                 [ [ row["monster"], row["count"] ], [ row["monster_2"], row["count_2"] ] ]
                   .reject { |slug, _| slug.blank? }.to_h { |slug, count| [ slug, JsonCasting.integer(count) || 1 ] }
      next if monsters.empty?

      { "weight" => JsonCasting.integer(row["weight"]) || 1, "monsters" => monsters }
    end)
  end

  def total_weight
    entries.sum { |entry| entry["weight"].to_i }
  end

  def monsters
    world.monsters.where(slug: entries.flat_map { |e| e["monsters"].keys }.uniq).index_by(&:slug)
  end

  private

  def entries_are_monster_groups
    errors.add(:entries, "need at least one monster group") if entries.empty?
    known = world ? world.monsters.pluck(:slug) : []
    entries.each_with_index do |entry, i|
      label = "group #{i + 1}"
      errors.add(:entries, "#{label} weight must be a positive whole number") unless JsonCasting.integer?(entry["weight"]) && entry["weight"].positive?
      entry["monsters"].each do |slug, count|
        errors.add(:entries, "#{label}: #{slug} is not in the Bestiary") unless known.include?(slug)
        errors.add(:entries, "#{label}: #{slug} count must be 1–#{MAX_GROUP}") unless JsonCasting.integer?(count) && count.between?(1, MAX_GROUP)
      end
    end
  end
end
