# frozen_string_literal: true

# What the setting is made of, as its author writes it: its damage types and
# terrain, the skills checks are made with, where characters come from, and
# its calendar. The books are checked against these.
module World::Setting
  extend ActiveSupport::Concern

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

  # Where characters can come from: [{ "slug", "name", "description",
  # "skill" }]. An origin's skill (one of the world's) gets a bonus.
  ORIGIN_BONUS = 10

  included do
    # A world that never thinks about types has one: Normal. Its skills
    # start as the base world's, to be renamed and replaced.
    before_validation(on: :create) do
      self.damage_types = [ { "slug" => "normal", "name" => "Normal", "colour" => TypeChart::DEFAULT_COLOURS["normal"] } ] if damage_types.blank?
      self.skills = DEFAULT_SKILLS if skills.blank?
    end

    validate :types_make_a_chart
    validate :terrain_types_are_types
    validate :skills_are_skills
    validate :origins_are_origins
  end

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

  def origin(slug)
    Array(origins).find { |o| o["slug"] == slug.to_s }
  end

  # A campaign's day as the setting names it: "Moonsday, 12 Rainfall", or
  # "Day 12" for a world with no calendar.
  #   calendar: { "weekdays" => [...], "months" => [...], "month_length" => 30 }
  def date(day)
    weekdays = Array(calendar["weekdays"]).compact_blank
    months = Array(calendar["months"]).compact_blank
    length = calendar["month_length"].to_i
    index = day.to_i - 1
    [ (weekdays[index % weekdays.size] if weekdays.any?),
      (months.any? && length.positive? ? "#{(index % length) + 1} #{months[(index / length) % months.size]}" : "day #{day}") ]
      .compact.join(", ").upcase_first
  end

  # From the form: names as comma-separated text.
  def calendar=(value)
    value = value.to_h.stringify_keys
    split = ->(v) { (v.is_a?(Array) ? v : v.to_s.split(",")).map { |n| n.to_s.strip }.reject(&:empty?).first(24) }
    super({ "weekdays" => split.(value["weekdays"]), "months" => split.(value["months"]),
            "month_length" => value["month_length"].to_i.clamp(0, 400) }.reject { |_, v| v.blank? })
  end

  private

  def types_make_a_chart
    type_chart.errors.each { |problem| errors.add(:damage_types, problem) }
  end

  def terrain_types_are_types
    bad = terrain_types.to_h.reject { |place, type| EncounterTable::TERRAINS.include?(place) && type_chart.include?(type) }
    errors.add(:terrain_types, "names unknown places or types: #{bad.keys.join(', ')}") if bad.any?
  end

  def origins_are_origins
    Array(origins).each do |origin|
      errors.add(:origins, "#{origin['slug'].inspect} isn't a usable id") unless origin["slug"].to_s.match?(TypeChart::SLUG)
      errors.add(:origins, "#{origin['slug']} needs a name") if origin["name"].blank?
      errors.add(:origins, "#{origin['name']}: #{origin['skill']} isn't one of the skills") if origin["skill"].present? && !skill(origin["skill"])
    end
    dupes = Array(origins).map { |o| o["slug"] }.tally.select { |_, n| n > 1 }.keys
    errors.add(:origins, "#{dupes.join(', ')} appear more than once") if dupes.any?
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
end
