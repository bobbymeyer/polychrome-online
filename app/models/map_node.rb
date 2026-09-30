# frozen_string_literal: true

# A point on a campaign's pointcrawl map (§4, §7). Hidden until the GM
# reveals it or the party arrives.
class MapNode < ApplicationRecord
  KINDS = %w[town dungeon landmark wilds field event].freeze
  WIDTH = 1000
  HEIGHT = 700

  belongs_to :campaign
  belongs_to :location, optional: true
  belongs_to :world_place, optional: true
  has_many :home_characters, class_name: "Character", foreign_key: :home_node_id, dependent: :nullify, inverse_of: :home_node
  has_many :outgoing_edges, class_name: "MapEdge", foreign_key: :from_node_id, dependent: :destroy, inverse_of: :from_node
  has_many :incoming_edges, class_name: "MapEdge", foreign_key: :to_node_id, dependent: :destroy, inverse_of: :to_node
  # What's being said here, and the rumours the party heard here.
  has_many :rumour_places, dependent: :delete_all
  has_many :rumours_about, class_name: "Rumour", foreign_key: :about_id, dependent: :nullify, inverse_of: :about
  # Clocks this place is behind: clearing it stops them (Campaign#clear_place!).
  has_many :clocks, dependent: :nullify
  has_many :heard_rumours, class_name: "Rumour", foreign_key: :heard_at_id, dependent: :nullify, inverse_of: :heard_at

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :x, numericality: { only_integer: true, in: 0..WIDTH }
  validates :y, numericality: { only_integer: true, in: 0..HEIGHT }
  validate { Pastime.parse(activities, campaign.world.almanac).last.each { |problem| errors.add(:activities, problem) } }

  before_destroy { campaign.update_columns(current_node_id: nil) if campaign.current_node_id == id }
  after_commit { campaign.table_changed }

  def edges
    campaign.map_edges.where(from_node: self).or(campaign.map_edges.where(to_node: self))
  end

  # Things to do here (Pastime): the setting's (its atlas place's, live, as
  # worlds are), then the GM's own, then those of the modes it's in now
  # (LocationMode#activities), by name, so a later one can replace one. A
  # mode can shut the usual ones ("pastimes" in what it closes).
  def pastimes
    almanac = campaign.world.almanac
    usual = location&.shut_by("pastimes") ? [] : Pastime.list(world_place&.activities, almanac) + Pastime.list(activities, almanac)
    in_modes = location ? location.modes_on.flat_map { |mode| Pastime.list(mode.activities, almanac) } : []
    (usual + in_modes).reverse.uniq(&:name).reverse
  end

  # What the setting says it's like here after dark (WorldPlace#night_line).
  def night_line = world_place&.night_line.presence

  def party_here?
    campaign.current_node_id == id
  end
end
