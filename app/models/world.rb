# frozen_string_literal: true

# The root of a setting. Every book entry belongs to exactly one world; the
# base world is seed data (db/seeds). A second author's world is just
# another row (§1, §9.1).
class World < ApplicationRecord
  include Vocabulary, Setting, Music, Copying, LineLists

  belongs_to :owner, class_name: "User", optional: true
  # In the order they go when the world does: the foreign keys are plain,
  # so whatever points at something goes before it (spec/models/deleting_spec.rb).
  # Campaigns and battles first (they use the books), then the canon (it
  # points into the books), then the books themselves.
  has_many :campaigns, dependent: :destroy
  has_many :battles, class_name: "BattleRecord", dependent: :destroy
  has_many :art_batches, dependent: :destroy
  has_many :world_fronts, dependent: :destroy # at places and figures
  has_many :world_figures, dependent: :destroy # at places and monsters
  has_many :world_routes, dependent: :destroy # at places and encounter tables
  has_many :world_places, dependent: :destroy # at location templates
  has_many :world_maps, dependent: :destroy # at places
  has_many :world_map_links, dependent: :destroy
  has_many :codex_entries, dependent: :destroy
  has_many :jobs, dependent: :destroy # at abilities
  has_many :abilities, dependent: :destroy
  has_many :items, dependent: :destroy
  has_many :monsters, dependent: :destroy
  has_many :location_templates, dependent: :destroy # at encounter tables
  has_many :encounter_tables, dependent: :destroy
  has_many :generator_tables, dependent: :destroy
  has_many :art_types, dependent: :destroy

  before_validation(on: :create) { self.slug = name.to_s.parameterize(separator: "_") if slug.blank? }

  validates :name, presence: true
  # "Persona-Scratch" is taken as persona_scratch: the address wants underscores.
  normalizes :slug, with: ->(slug) { slug.to_s.strip.downcase.tr("- ", "__") }
  validates :slug, presence: true, uniqueness: true,
                   format: { with: BookEntry::SLUG_FORMAT, message: "must be lowercase letters, digits and underscores, starting with a letter" }

  # A world can go once nobody plays in it; the Base World never does.
  def refuse_deleting!
    raise Refusal, "The Base World stays: the others are copied from it" if slug == "base"
    return unless campaigns.exists?

    raise Refusal, "#{campaigns.count == 1 ? 'A campaign is' : "#{campaigns.count} campaigns are"} played in #{name} (#{campaigns.order(:name).pluck(:name).uniq.first(3).to_sentence}). Those go first."
  end

  # From the form: a box per rule, on or off.
  def battle_rules=(value)
    value = value.to_h.stringify_keys
    super(Battle::RULES.select { |rule| ActiveModel::Type::Boolean.new.cast(value[rule]) }.index_with(true))
  end

  def rule?(rule) = battle_rules.to_h[rule.to_s] == true

  def to_param
    slug_in_database || slug
  end

  def art_loras=(value)
    super(ArtDirection.loras(value))
  end

  # The surnames its generator tables offer (families of a place's past).
  # What its histories and the pasts of its places are made of (Generators::Lore), from its lore tables.
  def lore
    @lore ||= Generators::Lore.from_tables(generator_tables.where(kind: GeneratorTable::LORE_KINDS).order(:id)
                                                           .group_by(&:kind).transform_values { |tables| tables.flat_map(&:entries) })
  end

  def reload(*)
    @lore = @family_names = nil
    super
  end

  def family_names
    @family_names ||= generator_tables.of_kind("families").flat_map { |t| t.entries.filter_map { |e| e["text"] } }
  end

  # A content type's framing (§8), made from config/comfy.yml the first time.
  # The map everything starts on: the first one, made the first time it's asked for.
  def root_map
    world_maps.in_order.first || world_maps.create!(name: name)
  end

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
                        terrain: terrain, types: type_chart.to_engine, summons: summon_library, rules: battle_rules)
  end
end
