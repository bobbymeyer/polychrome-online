# frozen_string_literal: true

# The root of a setting. Every book entry belongs to exactly one world; the
# base world is seed data (db/seeds). A second author's world is just
# another row (§1, §9.1).
class World < ApplicationRecord
  belongs_to :owner, class_name: "User", optional: true
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

  # Music for each kind of scene, uploaded by the world's author. Every page
  # at the table asks for one (ApplicationHelper#music_meta); a scene with
  # no track is silent. The jingles are synthesised (sound.js), so they need
  # nothing uploaded.
  MUSIC = %w[field town dungeon battle boss].freeze
  MUSIC_MAX_BYTES = 25.megabytes
  MUSIC.each { |scene| has_one_attached :"music_#{scene}" }
  validate :music_is_audio

  before_validation(on: :create) { self.slug = name.to_s.parameterize(separator: "_") if slug.blank? }
  # A world that never thinks about types has one: Normal. Its skills
  # start as the base world's, to be renamed and replaced.
  before_validation(on: :create) do
    self.damage_types = [ { "slug" => "normal", "name" => "Normal", "colour" => TypeChart::DEFAULT_COLOURS["normal"] } ] if damage_types.blank?
    self.skills = DEFAULT_SKILLS if skills.blank?
  end

  # Skills are what checks are made with (Stats::Check): each rides on a
  # stat, and a job can be good at some (+Job::SKILL_BONUS).
  #   { "slug" => "stealth", "name" => "Stealth", "stat" => "agi", "description" => "..." }
  DEFAULT_SKILLS = [
    { "slug" => "athletics", "name" => "Athletics", "stat" => "str", "description" => "Climbing, swimming, shoving, lifting the gate." },
    { "slug" => "endurance", "name" => "Endurance", "stat" => "vit", "description" => "Marching on, holding a breath, shrugging off the cold." },
    { "slug" => "stealth", "name" => "Stealth", "stat" => "agi", "description" => "Not being seen or heard." },
    { "slug" => "thievery", "name" => "Thievery", "stat" => "agi", "description" => "Locks, traps, pockets." },
    { "slug" => "lore", "name" => "Lore", "stat" => "mag", "description" => "Old scripts, crystals, what that sigil means." },
    { "slug" => "insight", "name" => "Insight", "stat" => "spr", "description" => "Reading a person, a lie, a mood." },
    { "slug" => "survival", "name" => "Survival", "stat" => "vit", "description" => "Tracks, weather, finding the way and something to eat." },
    { "slug" => "persuasion", "name" => "Persuasion", "stat" => "spr", "description" => "Talking someone round." }
  ].freeze

  validate :types_make_a_chart
  validate :terrain_types_are_types
  validate :skills_are_skills

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: BookEntry::SLUG_FORMAT }

  def to_param
    slug_in_database || slug
  end

  # --- types and skills ------------------------------------------------------

  def type_chart
    TypeChart.new(damage_types)
  end

  # The type of a fight on this terrain; the plain type where the world
  # doesn't say, or names a type it no longer has.
  def terrain_type(terrain)
    type = terrain_types.to_h[terrain.to_s]
    type_chart.include?(type) ? type : type_chart.plain
  end

  def skill(slug)
    skills.find { |s| s["slug"] == slug.to_s }
  end

  def skill_name(slug)
    skill(slug)&.fetch("name") || slug.to_s.humanize
  end

  def music_track(scene)
    return unless MUSIC.include?(scene.to_s)

    track = public_send(:"music_#{scene}")
    track if track.attached?
  end

  # Where a scene's track is served from, or nil for silence.
  def music_path(scene)
    track = music_track(scene)
    Rails.application.routes.url_helpers.rails_blob_path(track, only_path: true) if track
  end

  def copy_music_from!(source)
    MUSIC.each { |scene| (track = source.music_track(scene)) && public_send(:"music_#{scene}").attach(track.blob) }
  end

  def art_loras=(value)
    super(ArtDirection.loras(value))
  end

  BOOKS = %i[abilities items monsters encounter_tables generator_tables location_templates jobs].freeze

  # Start a new world from another one's books: every entry is copied
  # (images too, sharing the stored file), so the author edits a working
  # setting instead of an empty one. Books refer to each other by slug, so
  # copies keep pointing at copies; the few id references are remapped.
  # Copied in dependency order, so each entry validates against the ones
  # it names.
  def copy_books_from!(source)
    transaction do
      # The setting's types and skills first: the books are checked against them.
      update!(damage_types: source.damage_types, terrain_types: source.terrain_types, skills: source.skills)
      tables = {}
      abilities = {}
      BOOKS.each do |book|
        source.public_send(book).find_each do |entry|
          copy = entry.dup
          copy.world = self
          copy.encounter_table_id = tables[entry.encounter_table_id] if book == :location_templates
          copy.save!
          copy.image.attach(entry.image.blob) if entry.image.attached?
          tables[entry.id] = copy.id if book == :encounter_tables
          abilities[entry.id] = copy.id if book == :abilities
          if book == :jobs
            entry.job_levels.each { |level| copy.job_levels.create!(level: level.level, ability_id: abilities.fetch(level.ability_id)) }
          end
        end
      end
      source.art_types.each { |type| art_types.create!(type.attributes.except("id", "world_id", "created_at", "updated_at")) }
      %w[art_style art_negative art_loras art_checkpoint].each { |attr| self[attr] = source[attr] if self[attr].blank? }
      save!
    end
  end

  # A content type's framing (§8), made from config/comfy.yml the first time.
  def art_type(kind)
    art_types.find_by(kind: kind) || art_types.create!(kind: kind, **ArtType.defaults_for(kind).symbolize_keys)
  rescue ActiveRecord::RecordNotUnique
    art_types.find_by!(kind: kind)
  end

  # The world's Grimoire in the resolver's library format.
  def ability_library
    abilities.in_battle.to_h { |ability| [ ability.slug, ability.to_engine ] }
  end

  # Build a battle straight from the books.
  #   world.battle(seed: 1, party: [...unit specs], monsters: { "goblin" => 3 })
  def battle(seed:, party:, monsters:, escapable: true, items: {}, terrain: nil)
    by_slug = self.monsters.where(slug: monsters.keys).index_by(&:slug)
    enemies = monsters.map do |slug, count|
      by_slug.fetch(slug.to_s) { raise ActiveRecord::RecordNotFound, "no monster #{slug} in #{self.slug}" }.to_engine(count: count)
    end
    Battle::State.build(seed: seed, party: party, enemies: enemies, abilities: ability_library, escapable: escapable, items: items,
                        terrain: terrain, types: type_chart.to_engine)
  end

  private

  def types_make_a_chart
    type_chart.errors.each { |problem| errors.add(:damage_types, problem) }
  end

  def terrain_types_are_types
    bad = terrain_types.to_h.reject { |place, type| EncounterTable::TERRAINS.include?(place) && type_chart.include?(type) }
    errors.add(:terrain_types, "names unknown places or types: #{bad.keys.join(', ')}") if bad.any?
  end

  def skills_are_skills
    errors.add(:skills, "need at least one") if skills.blank?
    Array(skills).each do |skill|
      errors.add(:skills, "#{skill['slug'].inspect} isn't a usable id") unless skill["slug"].to_s.match?(TypeChart::SLUG)
      errors.add(:skills, "#{skill['slug']} needs a name") if skill["name"].blank?
      errors.add(:skills, "#{skill['name']} must use one of #{Stats::Check::STATS.join(', ')}") unless Stats::Check::STATS.include?(skill["stat"])
    end
    dupes = Array(skills).map { |s| s["slug"] }.tally.select { |_, n| n > 1 }.keys
    errors.add(:skills, "#{dupes.join(', ')} appear more than once") if dupes.any?
  end

  def music_is_audio
    MUSIC.each do |scene|
      track = public_send(:"music_#{scene}")
      next unless track.attached?

      errors.add(:"music_#{scene}", "must be an audio file") unless track.blob.content_type.to_s.start_with?("audio/")
      errors.add(:"music_#{scene}", "must be under #{MUSIC_MAX_BYTES / 1.megabyte} MB") if track.blob.byte_size > MUSIC_MAX_BYTES
    end
  end
end
