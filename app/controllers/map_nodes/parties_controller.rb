# frozen_string_literal: true

# The GM putting the party somewhere on the map directly (Campaign#place_party!).
class MapNodes::PartiesController < ApplicationController
  include MapGm

  before_action :set_node
  before_action :require_gm

  def create
    @campaign.place_party!(@node)
    panel notice: "The party is at #{@node.name}."
  end

  private

  def set_node
    @node = MapNode.find(params[:map_node_id])
    @campaign = @node.campaign
    @world = @campaign.world
  end
end
