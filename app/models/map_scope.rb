# frozen_string_literal: true

# Where a map's pieces are edited and looked at, for the one map sheet
# (maps/_sheet) drawn at both levels: a setting's atlas (WorldMap,
# WorldPlace, WorldRoute) and a campaign's maps (Map, MapNode, MapEdge),
# and for both uses, the table (looking, browsing, the GM steering) and the
# editor (the GM's, or a world editor's).
class MapScope
  include Rails.application.routes.url_helpers

  attr_reader :owner, :use

  # owner: a World or a Campaign. use: :table or :editor.
  def initialize(owner, use:, gm: false)
    @owner = owner
    @use = use
    @gm = gm
  end

  def world? = owner.is_a?(World)
  def campaign? = owner.is_a?(Campaign)
  def editor? = use == :editor
  def table? = use == :table
  # At the table: whether this viewer steers the stage (the GM) or browses alone.
  def gm? = @gm

  def maps = world? ? owner.world_maps.in_order : owner.maps.in_order
  def root_map = owner.root_map

  # Where a map is looked at: the editor's page for it, or the table's frame.
  def map_url(map)
    if editor?
      world? ? world_world_places_path(owner, map: map.id) : campaign_maps_path(owner, map: map.id)
    else
      campaign_map_view_path(owner, map: map.id)
    end
  end

  def steer_url(map) = campaign_map_view_path(owner, map: map.id)

  def new_place_url(map, x, y)
    world? ? new_world_world_place_path(owner, world_map_id: map.id, x: x, y: y) : new_campaign_map_node_path(owner, map_id: map.id, x: x, y: y)
  end

  def edit_place_url(place) = world? ? edit_world_world_place_path(owner, place) : edit_map_node_path(place)
  def update_place_url(place) = world? ? world_world_place_path(owner, place, format: :json) : map_node_path(place, format: :json)
  def edit_road_url(road) = world? ? edit_world_world_route_path(owner, road) : edit_map_edge_path(road)
  def update_road_url(road) = world? ? world_world_route_path(owner, road, format: :json) : map_edge_path(road, format: :json)
  def update_map_url(map) = world? ? world_world_map_path(owner, map, format: :json) : campaign_map_path(owner, map, format: :json)

  # Where a place leads when pressed at the table: its page, if it has one.
  def place_page(place)
    return unless campaign? && place.respond_to?(:location) && place.location

    location_path(place.location)
  end

  # The frame the editor's forms open in.
  def panel_id = world? ? "atlas_panel" : "map_panel"
end
