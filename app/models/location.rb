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

  include Generation, Modes, Tailoring, Town, Exploration

  validates :seed, numericality: { only_integer: true }
  validate :template_from_this_world

  before_validation(on: :create) { self.seed ||= Location.new_seed }

  # Rails 8 page refreshes: each viewer re-fetches their own page, so a
  # player's copy never contains what only the GM may see.
  after_update_commit :broadcast_refresh
  after_save { @generated = @view = nil }

  delegate :town?, :dungeon?, :kind, to: :location_template

  def self.new_seed
    Random.new_seed % 2**31
  end

  def name
    view["name"]
  end

  private

  def template_from_this_world
    return unless location_template && campaign

    errors.add(:location_template, "must come from #{campaign.world.name}") unless location_template.world_id == campaign.world_id
  end
end
