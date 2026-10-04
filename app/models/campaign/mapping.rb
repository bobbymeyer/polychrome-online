# frozen_string_literal: true

# A campaign's maps (Map; docs/HANDOFF.md §7, "Maps"), and the stage's map
# view: the GM puts a map on the stage for everyone (#show_map!), steps
# between maps on it, and takes it off (#show_place!). Players browse on
# their own screens without moving anyone.
module Campaign::Mapping
  extend ActiveSupport::Concern

  STAGE_VIEWS = %w[here map].freeze

  included do
    validates :stage_view, inclusion: { in: STAGE_VIEWS }
    validate { errors.add(:shown_map, "isn't one of this campaign's maps") if shown_map && shown_map.campaign_id != id }
  end

  # The map everything starts on: the setting's root map's copy, made the
  # first time it's asked for.
  def root_map
    maps.in_order.first || maps.create!(name: world.name, world_map: world.world_maps.in_order.first)
  end

  # The map the party is on, if they're anywhere.
  def party_map = current_node&.map

  def map_on_stage? = stage_view == "map"

  # What the stage's map view shows: the one the GM put there, else the
  # party's, else the first (nil until the campaign has a map: looking
  # never makes one, so a render never sets off another refresh).
  def map_shown
    shown_map || party_map || maps.in_order.first
  end

  def show_map!(map = map_shown || root_map)
    raise Refusal, "That isn't one of this campaign's maps" unless map.campaign_id == id

    update!(stage_view: "map", shown_map: map)
  end

  def show_place!
    update!(stage_view: "here", shown_map: nil)
  end
end
