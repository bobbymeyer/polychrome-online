# frozen_string_literal: true

# A world's damage types (World#damage_types): what the setting has, how
# each fares against the others, and which statuses each shrugs off. Rows
# are plain JSON, in the world's order; the first type is the plain one,
# the type of a fight that's nowhere in particular.
#
#   { "slug" => "fire", "name" => "Fire", "colour" => "#e8702a",
#     "shrugs_off" => [], "against" => { "grass" => 200, "water" => 50 } }
#
# A world can have one type or many. With one, types don't matter: every
# blow lands as it is, and the books and the table stop showing them.
class TypeChart
  # What a cell of the chart can say.
  PERCENTS = { 200 => "×2", 50 => "½", 0 => "0" }.freeze
  SLUG = /\A[a-z][a-z0-9_]*\z/
  COLOUR = /\A#\h{6}\z/

  DEFAULT_COLOURS = {
    "normal" => "#9a9a78", "fire" => "#e8702a", "water" => "#4f82e8", "electric" => "#f2c91c", "grass" => "#5fae3a",
    "ice" => "#7fd0cc", "fighting" => "#b52a24", "poison" => "#963a94", "ground" => "#d9b252", "flying" => "#8f76e8",
    "psychic" => "#f24b7d", "bug" => "#93a616", "rock" => "#a8932c", "ghost" => "#634a88", "dark" => "#5e4a3c", "steel" => "#9c9cb8"
  }.freeze
  # Where a fight is decides its type (a Geomancer's arts take it).
  DEFAULT_TERRAIN = { "plains" => "normal", "forest" => "grass", "desert" => "ground", "mountain" => "rock",
                      "cave" => "rock", "crypt" => "ghost", "sea" => "water", "town" => "normal" }.freeze
  NEW_COLOUR = "#8a8a8a"

  Type = Data.define(:slug, :name, :colour, :shrugs_off, :against)

  # The base world's: Pokémon's chart, less fairy and dragon (Battle::Types).
  def self.default_rows
    Battle::Types::DEFAULT["chart"].map do |slug, against|
      { "slug" => slug, "name" => slug.capitalize, "colour" => DEFAULT_COLOURS.fetch(slug, NEW_COLOUR),
        "shrugs_off" => Battle::Types::DEFAULT["shrugs_off"].fetch(slug, []), "against" => against }
    end
  end

  attr_reader :types

  def initialize(rows)
    @types = Array(rows).map do |row|
      Type.new(slug: row["slug"].to_s, name: row["name"].to_s, colour: row["colour"].presence || NEW_COLOUR,
               shrugs_off: Array(row["shrugs_off"]), against: row["against"].to_h)
    end
  end

  def slugs
    types.map(&:slug)
  end

  def include?(slug)
    slugs.include?(slug.to_s)
  end

  def [](slug)
    types.find { |t| t.slug == slug.to_s }
  end

  def plain
    slugs.first
  end

  # Do types come into this world at all? Not with only one.
  def matter?
    types.size > 1
  end

  def name(slug)
    self[slug]&.name || slug.to_s.humanize
  end

  def colour(slug)
    self[slug]&.colour || NEW_COLOUR
  end

  # Dark text on a light colour, white on a dark one.
  def ink(slug)
    r, g, b = colour(slug).delete_prefix("#").scan(/../).map { |h| h.to_i(16) }
    (r * 299 + g * 587 + b * 114) / 1000 > 160 ? "ink" : "paper"
  end

  def percent(attacking, defending)
    self[attacking]&.against&.fetch(defending, 100) || 100
  end

  # The battle engine's shape (Battle::Types).
  def to_engine
    {
      "chart" => types.to_h { |t| [ t.slug, t.against.select { |other, _| include?(other) } ] },
      "shrugs_off" => types.to_h { |t| [ t.slug, t.shrugs_off ] }.reject { |_, statuses| statuses.empty? }
    }
  end

  # Problems with the rows, for World's validation.
  def errors
    problems = []
    problems << "need at least one type" if types.empty?
    types.each do |t|
      problems << "#{t.slug.inspect} isn't a usable id (lowercase letters, digits, _)" unless t.slug.match?(SLUG)
      problems << "#{t.slug} needs a name" if t.name.blank?
      problems << "#{t.name}: colour must look like #a1b2c3" unless t.colour.match?(COLOUR)
      unknown = t.shrugs_off - Battle::STATUSES
      problems << "#{t.name} shrugs off unknown statuses: #{unknown.join(', ')}" if unknown.any?
      t.against.each do |other, percent|
        problems << "#{t.name} against unknown type #{other}" unless include?(other)
        problems << "#{t.name} against #{other} must be 0, 50 or 200" unless PERCENTS.key?(percent)
      end
    end
    dupes = slugs.tally.select { |_, n| n > 1 }.keys
    problems << "#{dupes.join(', ')} appear more than once" if dupes.any?
    problems
  end
end
