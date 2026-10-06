# frozen_string_literal: true

# What a map is, at either level (WorldMap for a setting, Map for a
# campaign; docs/HANDOFF.md §7, "Maps"): a 16:9 picture (uploaded, or made
# like a place's picture: Artwork) with a parent it sits on at x, y like a
# place does, children that sit on it, and siblings off its edges by
# direction (MapLinks: "B is east of A" is one link, read both ways).
# Everything drawn on a map is in MapNode::WIDTH × MapNode::HEIGHT.
module MapSheet
  extend ActiveSupport::Concern

  DIRECTIONS = %w[n e s w].freeze
  OPPOSITE = { "n" => "s", "s" => "n", "e" => "w", "w" => "e" }.freeze
  COMPASS = { "n" => "North", "e" => "East", "s" => "South", "w" => "West" }.freeze

  # Included after Artwork (whose hooks these override): a picture that can be made.
  included do
    has_one_attached :image

    normalizes :name, with: ->(name) { name.to_s.strip }
    validates :name, presence: true
    validates :x, numericality: { only_integer: true, in: 0..MapNode::WIDTH }, allow_nil: true
    validates :y, numericality: { only_integer: true, in: 0..MapNode::HEIGHT }, allow_nil: true
    validate :parent_is_not_itself_or_below
  end

  # Up from here to the root, nearest first.
  def ancestors
    chain = []
    up = parent
    while up && chain.size < 50
      chain << up
      up = up.parent
    end
    chain
  end

  # The siblings off each edge: { "n" => [map, ...], ... }, in the order they were linked.
  def neighbours
    DIRECTIONS.index_with { [] }.tap do |sides|
      links_out.includes(:to_map).order(:id).each { |link| sides[link.direction] << link.to_map }
      links_in.includes(:from_map).order(:id).each { |link| sides[OPPOSITE.fetch(link.direction)] << link.from_map }
    end
  end

  # Where the map is in the setting's words: "North of X", "On Y".
  def whereabouts
    parts = neighbours.filter_map { |direction, maps| "#{COMPASS.fetch(OPPOSITE.fetch(direction))} of #{maps.map(&:name).to_sentence}" if maps.any? }
    parts.unshift("On #{parent.name}") if parent
    parts.join(" · ")
  end

  # --- art (Artwork): a painted map of this land --------------------------------
  def art_kind = "map"
  def art_title = "the map of #{name}"
  def art_subject_label = name
  def art_subject = ArtDirection.join_prompt(name, art_notes.presence || description)
  def art_filename(seed) = "map-#{name.parameterize}-#{seed}.png"

  private

  def parent_is_not_itself_or_below
    return unless parent
    return errors.add(:parent, "can't be the map itself") if parent == self

    errors.add(:parent, "can't be one of this map's own children") if parent.ancestors.include?(self)
  end
end
