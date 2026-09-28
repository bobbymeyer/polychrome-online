# frozen_string_literal: true

# The root of a setting. Every book entry belongs to exactly one world; the
# base world is seed data (db/seeds). A second author's world is just
# another row (§1, §9.1).
class World < ApplicationRecord
  include Vocabulary, Setting, Music, Copying

  belongs_to :owner, class_name: "User", optional: true
  # The setting's canon, first: it points into the books below.
  has_many :world_figures, dependent: :destroy
  has_many :world_routes, dependent: :destroy
  has_many :world_places, dependent: :destroy
  has_many :codex_entries, dependent: :destroy
  has_many :world_fronts, dependent: :destroy
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

  before_validation(on: :create) { self.slug = name.to_s.parameterize(separator: "_") if slug.blank? }

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

  # The creatures the Grimoire's summons call, as engine unit specs.
  def summon_library
    creatures = abilities.flat_map { |a| Array(a.effects).filter_map { |e| e["creature"] if e["primitive"] == "summon" } }.uniq
    monsters.where(slug: creatures).to_h { |m| [ m.slug, m.to_engine.except("count") ] }
  end

  # The world's Grimoire in the resolver's library format.
  def ability_library
    abilities.in_battle.to_h { |ability| [ ability.slug, ability.to_engine ] }
  end

  # Build a battle straight from the books.
  #   world.battle(seed: 1, party: [...unit specs], monsters: { "goblin" => 3 })
  # extra_enemies: engine unit specs to add as they are (antagonists).
  def battle(seed:, party:, monsters:, escapable: true, items: {}, terrain: nil, extra_enemies: [])
    by_slug = self.monsters.where(slug: monsters.keys).index_by(&:slug)
    enemies = monsters.map do |slug, count|
      by_slug.fetch(slug.to_s) { raise ActiveRecord::RecordNotFound, "no monster #{slug} in #{self.slug}" }.to_engine(count: count)
    end + extra_enemies
    Battle::State.build(seed: seed, party: party, enemies: enemies, abilities: ability_library, escapable: escapable, items: items,
                        terrain: terrain, types: type_chart.to_engine, summons: summon_library)
  end
end
