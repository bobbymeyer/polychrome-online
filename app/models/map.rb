# frozen_string_literal: true

# One of a campaign's maps (docs/HANDOFF.md §7, "Maps"): the setting's,
# copied in (world_map), or the GM's own. Its places (MapNode) and child
# maps sit on it; its siblings are off its edges (MapLink). The stage shows
# one when the GM puts it there (Campaign#show_map!).
class Map < ApplicationRecord
  belongs_to :campaign
  belongs_to :world_map, optional: true
  belongs_to :parent, class_name: "Map", optional: true
  has_many :children, class_name: "Map", foreign_key: :parent_id, dependent: :nullify, inverse_of: :parent
  has_many :map_nodes, dependent: :nullify
  has_many :links_out, class_name: "MapLink", foreign_key: :from_map_id, dependent: :destroy, inverse_of: :from_map
  has_many :links_in, class_name: "MapLink", foreign_key: :to_map_id, dependent: :destroy, inverse_of: :to_map

  include MapSheet

  validates :name, uniqueness: { scope: :campaign_id }
  validate { errors.add(:parent, "isn't one of this campaign's maps") if parent && parent.campaign_id != campaign_id }

  before_destroy { campaign.update_columns(shown_map_id: nil) if campaign.shown_map_id == id }
  after_commit { campaign.table_changed }

  scope :in_order, -> { order(:id) }

  def places = map_nodes

  # The map the party is on: the one holding the place they're at.
  def party_here? = campaign.current_node&.map_id == id

  # Everything on it (MapNode) that the audience may see.
  def nodes_for(gm)
    nodes = map_nodes.includes(:location, :modes, :current_mode, campaign: :world).order(:id).to_a
    gm ? nodes : nodes.select(&:visible?)
  end

  # Roads with both ends on it.
  def edges_among(nodes)
    ids = nodes.map(&:id)
    campaign.map_edges.includes(:from_node, :to_node, :encounter_table).order(:id).select { |e| ids.include?(e.from_node_id) && ids.include?(e.to_node_id) }
  end
end
