# frozen_string_literal: true

# Brings a setting's canon into a campaign: its places onto the map (rolled
# from their fixed seeds, so Varn is the same Varn), the roads between them,
# and its cast as the campaign's NPCs. A campaign starts with all of it;
# later, whatever the world has gained can be brought in too. Nothing is
# brought in twice, and what's brought in is the campaign's to change.
class Atlas
  attr_reader :campaign

  def initialize(campaign)
    @campaign = campaign
  end

  def world = campaign.world

  def missing_places
    world.world_places.in_order.where.not(id: campaign.map_nodes.where.not(world_place_id: nil).select(:world_place_id))
  end

  def missing_figures
    world.world_figures.in_order.where.not(id: campaign.npcs.where.not(world_figure_id: nil).select(:world_figure_id))
  end

  def missing? = missing_places.exists? || missing_figures.exists?

  # Everything not yet here. Returns [places, figures] brought in.
  def bring_in_all!
    campaign.transaction { [ bring_in_places!, bring_in_figures! ] }
  end

  def bring_in_places!(places = missing_places)
    places = places.to_a
    campaign.transaction do
      places.each do |place|
        node = campaign.map_nodes.create!(name: place.name, kind: place.kind, x: place.x, y: place.y, visible: place.known,
                                          notes: place.notes, description: place.description, world_place: place)
        next unless place.location_template

        location = campaign.locations.create!(location_template: place.location_template, seed: place.seed, overrides: { "name" => place.name })
        node.update!(location: location)
        # What it's like by night: a mode that comes on at night by itself.
        location.add_mode!("name" => "By night", "line" => place.night_line, "times" => %w[night]) if place.night_line.present?
      end
      bring_in_routes!
      start_leads!(places)
    end
    places
  end

  # The talk that leads to places the party hasn't found (WorldPlace#lead),
  # started in the nearest town by road: hearing it there puts the place on
  # the map.
  def start_leads!(places)
    nodes = campaign.map_nodes.where(world_place: places.select(&:lead), visible: false).includes(:world_place)
    nodes.each do |node|
      town = campaign.nearest_town(node, through_blocked: true) or next # word gets over a blocked road
      campaign.start_rumour!(node.world_place.lead, at: town, about: node)
    end
  end

  # Roads whose two ends are both on the map now.
  def bring_in_routes!
    nodes = campaign.map_nodes.where.not(world_place_id: nil).index_by(&:world_place_id)
    have = campaign.map_edges.where.not(world_route_id: nil).pluck(:world_route_id)
    world.world_routes.where.not(id: have).find_each do |route|
      from = nodes[route.from_place_id]
      to = nodes[route.to_place_id]
      next unless from && to
      next if campaign.map_edges.where(from_node: from, to_node: to).or(campaign.map_edges.where(from_node: to, to_node: from)).exists?

      campaign.map_edges.create!(from_node: from, to_node: to, state: route.state, encounter_table: route.encounter_table,
                                 travel_event: route.travel_event, duration: route.duration, world_route: route)
    end
  end

  def bring_in_figures!(figures = missing_figures)
    figures = figures.includes(portraits: { image_attachment: :blob }).to_a
    homes = campaign.map_nodes.where.not(world_place_id: nil).where.not(location_id: nil).to_h { |n| [ n.world_place_id, n.location_id ] }
    campaign.transaction do
      figures.each do |figure|
        npc = campaign.npcs.create!(name: figure.name, title: figure.title, description: figure.description.presence || figure.blurb,
                                    art_notes: figure.art_notes, colour: figure.colour, monster: figure.monster,
                                    location_id: homes[figure.world_place_id], world_figure: figure)
        figure.portraits.each do |portrait|
          npc.portraits.create!(expression: portrait.expression).image.attach(portrait.image.blob) if portrait.image.attached?
        end
      end
    end
    figures
  end
end
