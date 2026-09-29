# frozen_string_literal: true

# A path between two map nodes (§4). Its state decides whether the party can
# cross and how likely an encounter is; its encounter table decides what the
# party meets; its travel event is narrated on the way.
class MapEdge < ApplicationRecord
  STATES = %w[open dangerous blocked].freeze

  belongs_to :campaign
  belongs_to :world_route, optional: true
  belongs_to :from_node, class_name: "MapNode", inverse_of: :outgoing_edges
  belongs_to :to_node, class_name: "MapNode", inverse_of: :incoming_edges
  belongs_to :encounter_table, optional: true

  normalizes :travel_event, with: ->(text) { text.presence }

  validates :state, inclusion: { in: STATES }
  validates :duration, numericality: { only_integer: true, in: 1..28 }
  validate :joins_two_nodes_of_this_campaign
  validate :one_path_per_pair
  validate :encounter_table_from_this_world

  after_commit { campaign.table_changed }

  def touches?(node)
    [ from_node_id, to_node_id ].include?(node.id)
  end

  def other_end(node)
    node.id == from_node_id ? to_node : from_node
  end

  # Players only see a path once both of its ends are revealed.
  def visible?
    from_node.visible? && to_node.visible?
  end

  def blocked?
    state == "blocked"
  end

  private

  def joins_two_nodes_of_this_campaign
    errors.add(:to_node, "must be a different place") if from_node_id == to_node_id
    [ from_node, to_node ].compact.each do |node|
      errors.add(:base, "#{node.name} is on another map") unless node.campaign_id == campaign_id
    end
  end

  def one_path_per_pair
    return unless from_node_id && to_node_id

    pair = campaign.map_edges.where(from_node_id: from_node_id, to_node_id: to_node_id)
                   .or(campaign.map_edges.where(from_node_id: to_node_id, to_node_id: from_node_id))
    errors.add(:base, "Those two places are already connected") if pair.where.not(id: id).exists?
  end

  def encounter_table_from_this_world
    return unless encounter_table && campaign

    errors.add(:encounter_table, "must come from #{campaign.world.name}") unless encounter_table.world_id == campaign.world_id
  end
end
