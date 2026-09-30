# frozen_string_literal: true

class MapNodesController < ApplicationController
  include CampaignScoped
  include MapGm

  before_action :set_campaign, only: %i[new create]
  before_action :set_node, only: %i[edit update destroy]
  before_action :require_table_gm

  def new
    @node = @campaign.map_nodes.new(x: params[:x].to_i.clamp(0, MapNode::WIDTH), y: params[:y].to_i.clamp(0, MapNode::HEIGHT))
    render layout: false
  end

  def create
    @node = @campaign.map_nodes.new(node_params)
    if @node.save
      redirect_to edit_map_node_path(@node), status: :see_other
    else
      render :new, layout: false, status: :unprocessable_content
    end
  end

  def edit
    render layout: false
  end

  # Also takes { x, y } alone from dragging on the map (a fetch, not the form).
  def update
    saved = @node.update(node_params)
    return head(saved ? :no_content : :unprocessable_content) if request.format.json?

    if saved
      redirect_to edit_map_node_path(@node), status: :see_other
    else
      render :edit, layout: false, status: :unprocessable_content
    end
  end

  def destroy
    @node.destroy!
    panel notice: "#{@node.name} was removed from the map."
  end

  private

  def set_node
    @node = MapNode.find(params[:id])
    @campaign = @node.campaign
    @world = @campaign.world
  end

  def node_params
    params.expect(map_node: %i[name kind x y visible notes description activities])
  end
end
