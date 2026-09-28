# frozen_string_literal: true

# The world moving while the party sleeps (Pointcrawl::Overnight): each new
# day, clocks that tick now and then may tick, rumours travel a road, an
# antagonist who got away turns up somewhere nearby, a caravan is lost on a
# dangerous road and prices move. It runs on the campaign's own dice, so
# it's the same night however often it's looked at. The GM gets a note of
# what happened; the party only learns it as rumours reach them.
module Campaign::Overnight
  extend ActiveSupport::Concern

  included do
    has_many :rumours, dependent: :delete_all
  end

  # People start talking about something at a place on the map. seen: the
  # party was there and saw it happen, so there's nothing to hear. sway: a
  # deed's, moving each town's view of the party as the news gets there.
  def start_rumour!(body, at:, also: [], seen: false, sway: 0, deed: nil, secret: nil)
    rumour = rumours.create!(body: body, origin: at, heard: seen, heard_day: (day if seen), heard_at: (at if seen),
                             sway: sway, deed: deed, secret: secret)
    rumour.reach!(([ at ] + also).compact, day: day)
    rumour
  end

  # What the party hears on reaching a place: every rumour that got there
  # before them. Only where there are people to talk to.
  def hear_rumours!(node = current_node)
    return [] unless node&.location

    # Not their own deed where they did it: they were there.
    rumours.travelling.unheard.at(node).where.not(id: rumours.about_deeds.where(origin: node).select(:id)).order(:id).each do |rumour|
      rumour.update!(heard: true, heard_day: day, heard_at: node)
      narrate(rumour.secret_id ? "In #{node.name}, someone whispers: “#{rumour.body}”" : "In #{node.name}, people are saying: “#{rumour.body}”")
    end
  end

  # A rumour nobody at the table has heard yet (the guild sells one).
  def rumour_for_sale
    rumours.travelling.unheard.where(deed_id: nil).order(:id).first
  end

  def overnight!
    nodes = map_nodes.includes(:location).to_a
    by_id = nodes.index_by(&:id)
    next_rng, happenings = Pointcrawl::Overnight.run(overnight_world(nodes), rng)
    notes = []
    transaction do
      update!(rng: next_rng)
      rumours.travelling.update_all("age = age + 1")
      happenings.each do |event|
        case event["kind"]
        when "clock"
          clock = clocks.find(event["clock"])
          clock.tick!(1, reason: Clock::REASONS["now_and_then"])
          notes << "#{clock.name} moved on (#{clock.filled} of #{clock.segments})."
        when "spread"
          rumours.find(event["rumour"]).reach!(event["to"], day: day)
        when "fade"
          rumours.find(event["rumour"]).update!(faded: true)
        when "moved"
          to = by_id.fetch(event["to"])
          npcs.find(event["npc"]).update!(location: to.location)
          start_rumour!("#{event['name']} was seen in #{to.name}.", at: to)
          notes << "#{event['name']} went from #{by_id[event['from']]&.name} to #{to.name}."
        when "caravan"
          from, to = by_id.values_at(event["from"], event["to"])
          start_rumour!("A caravan on the road between #{from.name} and #{to.name} was attacked.", at: from, also: [ to ])
          notes << "A caravan was lost between #{from.name} and #{to.name}."
        when "price"
          node = by_id.fetch(event["place"])
          node.location.update!(prices: event["shift"])
          notes << "Prices in #{node.name}: #{format('%+d', event['shift'])}%." if event["shift"].abs >= Pointcrawl::Overnight::CARAVAN_SHOCK
        when "leak"
          secret = secrets.find(event["secret"])
          at = by_id.fetch(event["at"])
          start_rumour!(secret.body, at: at, secret: secret)
          notes << "A secret got out in #{at.name}: #{secret.body}"
        end
      end
      narrate("Overnight: #{notes.join(' ')}", scope: "gm") if notes.any?
      hear_rumours!
    end
    happenings
  end

  private

  def overnight_world(nodes)
    {
      "places" => nodes.map { |n| { "id" => n.id, "name" => n.name, "town" => n.location&.town? || false, "settled" => !n.location.nil? } },
      "roads" => map_edges.map { |e| { "from" => e.from_node_id, "to" => e.to_node_id, "state" => e.state } },
      "clocks" => clocks.running.order(:id).select { |c| c.ticks_on?("now_and_then") }.map(&:id),
      "rumours" => rumours.travelling.includes(:rumour_places).order(:id).map { |r| { "id" => r.id, "reached" => r.reached, "age" => r.age } },
      "antagonists" => npcs.at_large.where("escapes > 0").includes(location: :map_node).order(:id)
                           .map { |n| { "id" => n.id, "name" => n.name, "at" => n.location&.map_node&.id } },
      "prices" => nodes.select { |n| n.location&.town? }.to_h { |n| [ n.id, n.location.prices ] },
      "secrets" => leakable_secrets
    }
  end

  # Kept secrets about somewhere on the map, not already going around.
  def leakable_secrets
    going = rumours.where.not(secret_id: nil).pluck(:secret_id)
    secrets.kept.where.not(id: going).includes(location: :map_node, npc: { location: :map_node }).order(:id).filter_map do |secret|
      node = secret.location&.map_node || secret.npc&.location&.map_node
      { "id" => secret.id, "at" => node.id } if node
    end
  end
end
