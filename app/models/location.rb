# frozen_string_literal: true

# A town or dungeon in a campaign (docs/HANDOFF.md §4, §7): a template, a
# seed, and GM overrides. What's in it is never stored; #view rolls it again
# every time (Location::Generation). The rest is in slices: its modes, the
# GM's changes, a town's people and a dungeon's exploration
# (app/models/location/).
class Location < ApplicationRecord
  belongs_to :campaign
  belongs_to :location_template
  has_many :mode_arts, dependent: :destroy
  has_one :map_node, dependent: :nullify
  has_many :npcs, dependent: :nullify

  include Generation, Tailoring, Town, Exploration

  validates :seed, numericality: { only_integer: true }
  validate :template_from_this_world

  before_validation(on: :create) { self.seed ||= Location.new_seed }

  # Rails 8 page refreshes: each viewer re-fetches their own page, so a
  # player's copy never contains what only the GM may see.
  after_update_commit :broadcast_refresh
  # A mode on the map, the party moving room to room.
  after_update_commit -> { campaign.table_changed }
  after_save { @generated = @view = nil }

  delegate :town?, :dungeon?, :kind, to: :location_template

  # Its modes are its place's on the map (MapNode::Modes): a town or dungeon
  # off the map has none.
  delegate :modes, :current_mode, :mode, :add_mode!, :remove_mode!, :switch_mode!, :clear_mode!, :mode_called,
           to: :map_node, allow_nil: false
  def modes_on(**) = map_node ? map_node.modes_on(**) : []
  def shut_by(kind) = map_node&.shut_by(kind)
  def service_closed?(kind) = shut_by(kind).present?

  # How a mode changes the place's picture (§8): words after the rest of
  # the prompt ("on fire, thick smoke, ash falling").
  def set_mode_art!(key, words)
    mode_called(key).update!(art: words)
  end

  # The place's picture as it is now: the first of its modes' own, if one
  # has one, else the Gazetteer entry's. nil when neither has been made.
  def picture
    in_mode = modes_on.filter_map(&:mode_art).find { |art| art.image.attached? }
    return in_mode.image if in_mode

    location_template.image if location_template.image.attached?
  end


  def self.new_seed
    Random.new_seed % 2**31
  end

  # What rolling a place reads, to preload with a list of them:
  #   clocks.includes(location_mode: { location: Location::ROLLING })
  ROLLING = [ :campaign, { map_node: :world_place }, { location_template: %i[world encounter_table] } ].freeze

  # Its name without the whole view: the GM's, else the rolled one.
  def name
    overrides["name"].to_s.strip.empty? ? generated["name"] : overrides["name"]
  end

  private

  def template_from_this_world
    return unless location_template && campaign

    errors.add(:location_template, "must come from #{campaign.world.name}") unless location_template.world_id == campaign.world_id
  end
end
