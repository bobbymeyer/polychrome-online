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
  has_many :front_clocks_from, class_name: "FrontClock", foreign_key: :source_id, dependent: :nullify, inverse_of: :source

  # What people say that leads to it ("Goblins come down from a cave in the
  # hills."), for a place the party hasn't found: it starts as a rumour in
  # the nearest town, and hearing it puts the place on the map (Atlas).
  normalizes :lead, with: ->(lead) { lead.to_s.strip.presence }

  normalizes :name, with: ->(name) { name.to_s.strip }

  validates :name, presence: true, uniqueness: { scope: :world_id }
  validates :kind, inclusion: { in: MapNode::KINDS }
  validates :x, numericality: { only_integer: true, in: 0..MapNode::WIDTH }
  validates :y, numericality: { only_integer: true, in: 0..MapNode::HEIGHT }
  validate :template_fits
  validate { Pastime.parse(activities).last.each { |problem| errors.add(:activities, problem) } }

  before_validation { self.seed ||= Location.new_seed if location_template }

  scope :in_order, -> { order(:name) }

  # Its past (Past), as the world's history wrote it; the GM changes it from
  # the form, and a changed past is theirs: the history won't write over it.
  # How it can have fallen: the world's falls (its lore), or left empty.
  def past_falls = world.lore["falls"].keys + %w[abandoned]

  def past_form
    fall = past["fall"].is_a?(Hash) ? past["fall"] : {}
    feud = past["feud"].is_a?(Hash) ? past["feud"] : {}
    { "founded" => past["founded"], "founder" => past["founder"], "family" => past["family"], "holder" => past["holder"],
      "rival" => past["rival"], "was" => past["was"], "fall_kind" => fall["kind"], "fall_ago" => fall["ago"],
      "lost" => Array(past["lost"]).join(", "), "feud_with" => feud["with"], "feud_cause" => feud["cause"] }
      .transform_values { |v| v.to_s }
  end

  def past_form=(fields)
    fields = fields.to_h.stringify_keys.transform_values { |v| v.to_s.strip }
    return if fields.slice(*past_form.keys) == past_form.slice(*fields.keys)

    built = {
      "founded" => fields["founded"].presence&.to_i, "founder" => fields["founder"].presence, "family" => fields["family"].presence,
      "holder" => fields["holder"].presence, "rival" => fields["rival"].presence,
      "was" => fields["was"].presence_in(world.lore["pasts"].keys),
      "fall" => (fields["fall_kind"].presence_in(past_falls) && { "kind" => fields["fall_kind"], "ago" => fields["fall_ago"].to_i }),
      "lost" => fields["lost"].to_s.split(",").map(&:strip).compact_blank.presence,
      "feud" => (fields["feud_with"].presence && { "with" => fields["feud_with"], "cause" => fields["feud_cause"].presence }.compact)
    }.compact
    self.past = built.empty? ? {} : past.slice("heirlooms", "makers", "founders_left").merge(built).merge("edited" => true)
  end

  private

  def template_fits
    return unless location_template

    errors.add(:location_template, "isn't one of #{world.name}'s") if location_template.world_id != world_id
    errors.add(:location_template, "is a #{location_template.kind}, and this is a #{kind}") if location_template.kind != kind
  end
end
