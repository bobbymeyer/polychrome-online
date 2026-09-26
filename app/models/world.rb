# frozen_string_literal: true

# The root of a setting. Every book entry belongs to exactly one world; the
# base world is seed data (db/seeds). A second author's world is just
# another row (§1, §9.1).
class World < ApplicationRecord
  has_many :abilities, dependent: :destroy
  has_many :items, dependent: :destroy
  has_many :jobs, dependent: :destroy
  has_many :monsters, dependent: :destroy
  has_many :encounter_tables, dependent: :destroy
  has_many :generator_tables, dependent: :destroy
  has_many :location_templates, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  has_many :battles, class_name: "BattleRecord", dependent: :destroy
  has_many :art_types, dependent: :destroy
  has_many :art_batches, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: BookEntry::SLUG_FORMAT }

  def to_param
    slug_in_database || slug
  end

  def art_loras=(value)
    super(ArtDirection.loras(value))
  end

  # A content type's framing (§8), made from config/comfy.yml the first time.
  def art_type(kind)
    art_types.find_by(kind: kind) || art_types.create!(kind: kind, **ArtType.defaults_for(kind).symbolize_keys)
  rescue ActiveRecord::RecordNotUnique
    art_types.find_by!(kind: kind)
  end

  # The world's Grimoire in the resolver's library format.
  def ability_library
    abilities.to_h { |ability| [ ability.slug, ability.to_engine ] }
  end

  # Build a battle straight from the books.
  #   world.battle(seed: 1, party: [...unit specs], monsters: { "goblin" => 3 })
  def battle(seed:, party:, monsters:, escapable: true, items: {})
    by_slug = self.monsters.where(slug: monsters.keys).index_by(&:slug)
    enemies = monsters.map do |slug, count|
      by_slug.fetch(slug.to_s) { raise ActiveRecord::RecordNotFound, "no monster #{slug} in #{self.slug}" }.to_engine(count: count)
    end
    Battle::State.build(seed: seed, party: party, enemies: enemies, abilities: ability_library, escapable: escapable, items: items)
  end
end
