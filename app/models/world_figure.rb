# frozen_string_literal: true

# Someone in a setting's cast: the Syndicate's boss, the saint in the
# cathedral. Written once in the world; a campaign brings them in as its own
# NPCs (Atlas), faces and all. Linked to a Bestiary entry, they're an
# antagonist in every campaign that brings them in.
#
# The blurb is what people say about them; the description is the GM's.
class WorldFigure < ApplicationRecord
  include Portrayed
  include Colourable

  belongs_to :world
  belongs_to :monster, optional: true
  belongs_to :world_place, optional: true
  has_many :npcs, dependent: :nullify

  normalizes :name, with: ->(name) { name.to_s.strip }

  validates :name, presence: true, uniqueness: { scope: :world_id }
  validate :of_this_world

  scope :in_order, -> { order(:name) }

  def fallback_portrait_entry = monster

  private

  def of_this_world
    errors.add(:monster, "isn't in #{world.name}'s Bestiary") if monster && monster.world_id != world_id
    errors.add(:world_place, "isn't in #{world.name}'s atlas") if world_place && world_place.world_id != world_id
  end
end
