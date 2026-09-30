# frozen_string_literal: true

# The world moving while the party sleeps (Pointcrawl::Overnight): each new
# day, clocks that tick now and then may tick, rumours travel a road, an
# antagonist who got away turns up somewhere nearby, a caravan is lost on a
# dangerous road and prices move. It runs on the campaign's own dice, so
# it's the same night however often it's looked at. The GM gets a note of
# what happened; the party only learns it as rumours reach them.
module Campaign::Overnight
  extend ActiveSupport::Concern

  # People start talking about something at a place on the map. seen: the
  # party was there and saw it happen, so there's nothing to hear. sway: a
  # deed's, moving each town's view of the party as the news gets there.
  def start_rumour!(body, at:, also: [], seen: false, sway: 0, deed: nil, secret: nil, about: nil)
    rumour = rumours.create!(body: body, origin: at, heard: seen, heard_day: (day if seen), heard_at: (at if seen),
                             sway: sway, deed: deed, secret: secret, about: about)
    rumour.reach!(([ at ] + also).compact, day: day)
    rumour
  end

  # What the party hears on reaching a place: every rumour that got there
  # before them. Only where there are people to talk to.
  def hear_rumours!(node = current_node)
    return [] unless node

    # Not their own deed where they did it: they were there.
    heard = rumours.travelling.unheard.at(node).where.not(id: rumours.about_deeds.where(origin: node).select(:id))
    # Somewhere nobody lives (a landmark, the wilds) only says what was set loose right there.
    heard = heard.where(origin: node) unless node.location
    heard.order(:id).each do |rumour|
      rumour.update!(heard: true, heard_day: day, heard_at: node)
      said = narrate(rumour.secret_id ? "In #{node.name}, someone whispers: “#{rumour.body}”" : "In #{node.name}, people are saying: “#{rumour.body}”")
      # A secret that got out is out: the party knows it now (the whisper was its telling).
      rumour.secret.update!(revealed_at: said.created_at, revealed_by: "Heard in #{node.name}") if rumour.secret && !rumour.secret.revealed?
      hear_of!(rumour)
    end
  end

  # A rumour that points somewhere puts the place on the map once it's heard
  # (Dragon Quest's townsfolk: "the cave north of here…").
  def hear_of!(rumour)
    place = rumour.about
    return unless place && !place.visible?

    place.update!(visible: true)
    narrate("#{place.name} is on the map now.")
  end

  # A rumour nobody at the table has heard yet (the guild sells one).
  def rumour_for_sale
    rumours.travelling.unheard.where(deed_id: nil).order(:id).first
  end

  def overnight!
    nodes = map_nodes.includes(:location).to_a
    by_id = nodes.index_by(&:id)
    notes = []
    happenings = nil
    transaction do
      happenings = roll_with { |state| Pointcrawl::Overnight.run(overnight_world(nodes), state) }
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
          villain_moves!(npcs.find(event["npc"]), from: by_id[event["from"]], to: to)
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

  # An antagonist moves in somewhere new: its master's room is theirs now,
  # even if the party already cleared it, and the clocks only they were
  # keeping going (their old place is cleared) go with them.
  def villain_moves!(villain, from:, to:)
    villain.update!(location: to.location)
    to.location.await_villain!
    return unless from&.location&.cleared? && !npcs.at_large.exists?(location_id: from.location.id)

    from.clocks.running.each { |clock| clock.update!(map_node: to) }
  end

  def overnight_world(nodes)
    {
      "places" => nodes.map { |n| { "id" => n.id, "name" => n.name, "town" => n.location&.town? || false, "settled" => !n.location.nil?, "lair" => n.location&.lair? || false } },
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
