# frozen_string_literal: true

class MapEdgesController < ApplicationController
  include CampaignScoped
  include MapGm

  before_action :set_from_node, only: :create
  before_action :set_edge, only: %i[edit update destroy]
  before_action :require_table_gm

  # Connect a node to another (from the node's panel).
  def create
    @edge = @campaign.map_edges.new(edge_params.merge(from_node: @from))
    if @edge.save
      redirect_to edit_map_edge_path(@edge), status: :see_other
    else
      flash[:map_alert] = @edge.errors.full_messages.to_sentence
      redirect_to edit_map_node_path(@from), status: :see_other
    end
  end

  def edit; end

  # The form, or from the map: a new bend where it was clicked ({ bend: { x, y } }),
  # or the bends as dragged ({ map_edge: { waypoints: [...] } }).
  def update
    bend = params[:bend].presence || params.dig(:map_edge, :bend).presence # JSON bodies are wrapped under map_edge
    @edge.bend_at(bend[:x].to_i, bend[:y].to_i) if bend
    saved = @edge.update(edge_params)
    return head(saved ? :no_content : :unprocessable_content) if request.format.json?

    if saved
      redirect_to edit_map_edge_path(@edge), status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @edge.destroy!
    panel notice: "The path between #{@edge.from_node.name} and #{@edge.to_node.name} was cut."
  end

  private

  def set_from_node
    @from = MapNode.find(params[:map_node_id])
    @campaign = @from.campaign
    @world = @campaign.world
  end

  def set_edge
    @edge = MapEdge.find(params[:id])
    @campaign = @edge.campaign
    @world = @campaign.world
  end

  # The bends come as points ([[x, y], ...]), which strong parameters don't permit as such: read by hand (RoadBends#waypoints= checks them).
  def edge_params
    raw = params.fetch(:map_edge, {})
    fields = raw.permit(:to_node_id, :state, :encounter_table_id, :travel_event, :duration)
    fields[:waypoints] = Array(raw[:waypoints]).map { |pt| pt.respond_to?(:to_unsafe_h) ? pt.to_unsafe_h.values_at("x", "y") : Array(pt) } if raw.key?(:waypoints)
    fields
  end
end
