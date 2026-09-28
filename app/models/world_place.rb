# frozen_string_literal: true

# A place in a setting's atlas: the port city of Varn, the drowned abbey.
# Written once in the world; a campaign starts with it on its map (Atlas).
# A town or dungeon can be rolled from a Gazetteer template with a fixed
# seed, so Varn is the same Varn in every campaign. Players read its
# description; the notes are the GM's.
class WorldPlace < ApplicationRecord
  belongs_to :world
  belongs_to :location_template, optional: true
  has_many :outgoing_routes, class_name: "WorldRoute", foreign_key: :from_place_id, dependent: :destroy, inverse_of: :from_place
  has_many :incoming_routes, class_name: "WorldRoute", foreign_key: :to_place_id, dependent: :destroy, inverse_of: :to_place
  has_many :world_figures, dependent: :nullify
  has_many :map_nodes, dependent: :nullify

  normalizes :name, with: ->(name) { name.to_s.strip }

  validates :name, presence: true, uniqueness: { scope: :world_id }
  validates :kind, inclusion: { in: MapNode::KINDS }
  validates :x, numericality: { only_integer: true, in: 0..MapNode::WIDTH }
  validates :y, numericality: { only_integer: true, in: 0..MapNode::HEIGHT }
  validate :template_fits

  before_validation { self.seed ||= Location.new_seed if location_template }

  scope :in_order, -> { order(:name) }

  private

  def template_fits
    return unless location_template

    errors.add(:location_template, "isn't one of #{world.name}'s") if location_template.world_id != world_id
    errors.add(:location_template, "is a #{location_template.kind}, and this is a #{kind}") if location_template.kind != kind
  end
end
