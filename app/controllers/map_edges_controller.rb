# frozen_string_literal: true

class MapEdgesController < ApplicationController
  include CampaignScoped
  include MapGm

  before_action :set_from_node, only: :create
  before_action :set_edge, only: %i[edit update destroy]
  before_action :require_gm

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

  def edit
    render layout: false
  end

  def update
    if @edge.update(edge_params)
      redirect_to edit_map_edge_path(@edge), status: :see_other
    else
      render :edit, layout: false, status: :unprocessable_content
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

  def edge_params
    params.expect(map_edge: %i[to_node_id state encounter_table_id travel_event])
  end
end
