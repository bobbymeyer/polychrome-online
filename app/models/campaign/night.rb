# frozen_string_literal: true

# A night passing for a campaign (Pointcrawl::Overnight; docs/HANDOFF.md
# §7, "The world moves overnight"): each new day, clocks that tick now and
# then may tick, rumours travel a road, an antagonist who got away turns up
# somewhere nearby, a caravan is lost on a dangerous road and prices move,
# and a kept secret may leak. It runs on the campaign's own dice, so it's
# the same night however often it's looked at. The GM gets a note of what
# happened; the party only learns it as rumours reach them.
#
#   Campaign::Night.new(campaign).pass!   # on "dawn" (Campaign::Happenings)
class Campaign::Night
  attr_reader :campaign

  def initialize(campaign)
    @campaign = campaign
  end

  # Plays the night out on the campaign. Returns what happened
  # (Pointcrawl::Overnight's events).
  def pass!
    nodes = campaign.map_nodes.includes(:location).to_a
    @places = nodes.index_by(&:id)
    notes = []
    happenings = nil
    campaign.transaction do
      happenings = campaign.roll_with { |state| Pointcrawl::Overnight.run(world_tonight(nodes), state) }
      campaign.rumours.travelling.update_all("age = age + 1")
      happenings.each { |event| notes << happen!(event) }
      notes.compact!
      campaign.narrate("Overnight: #{notes.join(' ')}", scope: "gm") if notes.any?
      campaign.hear_rumours!
    end
    happenings
  end

  private

  # One thing that happened in the night, done; returns the GM's note of it, if it gets one.
  def happen!(event)
    case event["kind"]
    when "clock"
      clock = campaign.clocks.find(event["clock"])
      clock.tick!(1, reason: Campaign::Happenings::EVENTS["now_and_then"])
      "#{clock.name} moved on (#{clock.filled} of #{clock.segments})."
    when "spread"
      campaign.rumours.find(event["rumour"]).reach!(event["to"], day: campaign.day)
      nil
    when "fade"
      campaign.rumours.find(event["rumour"]).update!(faded: true)
      nil
    when "moved"
      from, to = @places[event["from"]], @places.fetch(event["to"])
      villain_moves!(campaign.npcs.find(event["npc"]), from: from, to: to)
      said = lore_line("sightings", event["npc"].to_i)
      campaign.start_rumour!(Generators::Lore.fill(said, who: event["name"], where: to.name), at: to) if said
      "#{event['name']} went from #{from&.name} to #{to.name}."
    when "caravan"
      from, to = @places.values_at(event["from"], event["to"])
      said = lore_line("raids", from.id + to.id)
      campaign.start_rumour!(Generators::Lore.fill(said, from: from.name, to: to.name), at: from, also: [ to ]) if said
      "A caravan was lost between #{from.name} and #{to.name}."
    when "price"
      node = @places.fetch(event["place"])
      node.location.update!(prices: event["shift"])
      "Prices in #{node.name}: #{format('%+d', event['shift'])}%." if event["shift"].abs >= Pointcrawl::Overnight::CARAVAN_SHOCK
    when "leak"
      secret = campaign.secrets.find(event["secret"])
      at = @places.fetch(event["at"])
      campaign.start_rumour!(secret.body, at: at, secret: secret)
      "A secret got out in #{at.name}: #{secret.body}"
    end
  end

  # One of the world's lines for what people say overnight (its lore); which
  # one follows from who and the day, so a night reads the same every time.
  def lore_line(kind, salt)
    lines = campaign.world.lore[kind]
    lines[(salt + campaign.day) % lines.size] if lines.any?
  end

  # An antagonist moves in somewhere new: its master's room is theirs now,
  # even if the party already cleared it, and the clocks only they were
  # keeping going (their old place is cleared) go with them.
  def villain_moves!(villain, from:, to:)
    villain.update!(location: to.location)
    to.location&.await_villain!
    return unless from&.location&.cleared? && !campaign.npcs.at_large.exists?(location_id: from.location.id)

    from.clocks.running.each { |clock| clock.update!(map_node: to) }
  end

  # The campaign's map tonight, as the pure step reads it.
  def world_tonight(nodes)
    {
      "places" => nodes.map { |n| { "id" => n.id, "name" => n.name, "town" => n.location&.town? || false, "settled" => !n.location.nil?, "lair" => n.location&.lair? || false } },
      "roads" => campaign.map_edges.map { |e| { "from" => e.from_node_id, "to" => e.to_node_id, "state" => e.state } },
      "clocks" => campaign.clocks.running.order(:id).select { |c| c.ticks_on?("now_and_then") }.map(&:id),
      "rumours" => campaign.rumours.travelling.includes(:rumour_places).order(:id).map { |r| { "id" => r.id, "reached" => r.reached, "age" => r.age } },
      "antagonists" => campaign.npcs.at_large.where("escapes > 0").includes(location: :map_node).order(:id)
                               .map { |n| { "id" => n.id, "name" => n.name, "at" => n.location&.map_node&.id } },
      "prices" => nodes.select { |n| n.location&.town? }.to_h { |n| [ n.id, n.location.prices ] },
      "secrets" => leakable_secrets
    }
  end

  # Kept secrets about somewhere on the map, not already going around.
  def leakable_secrets
    going = campaign.rumours.where.not(secret_id: nil).pluck(:secret_id)
    campaign.secrets.kept.where.not(id: going).includes(location: :map_node, npc: { location: :map_node }).order(:id).filter_map do |secret|
      node = secret.location&.map_node || secret.npc&.location&.map_node
      { "id" => secret.id, "at" => node.id } if node
    end
  end
end
