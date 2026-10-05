# frozen_string_literal: true

# Where the party can go from here, and the table deciding it (docs/DESIGN.md,
# "Players steer"). On the map, the open paths from where the party stands;
# in a dungeon, the ways on from the room they're in. Anyone at the table
# can put "Where next?" to a vote: a choice (Message) whose options carry
# the moves, so the GM settling it takes the party there. The GM can still
# just go. Staying is a way on too: what there is to do here this part of
# the day (Pastime) goes to the same vote, and takes its time.
module Campaign::Ways
  extend ActiveSupport::Concern

  STAY = "Stay here"

  # [{ "label" => "To Greymere (by a dangerous road)", "move" => { "edge" => id } }],
  # at a dungeon's door also { "label" => "Into Goblin Hollow", "move" => { "location" => id, "enter" => true } },
  # or, inside, [{ "label" => "The Ossuary", "move" => { "location" => id, "room" => key } }].
  # A room the players haven't seen is only "An unexplored way".
  # warn: what the GM is asked before just going (a dangerous road, a night).
  # None while everyone is KO'd: what happens then is decided first (Campaign::Defeat).
  def ways_on
    if wiped_out?
      []
    elsif (dungeon = dungeon_in_progress)
      dungeon_ways(dungeon)
    elsif current_node
      inside = current_node.location
      way_in = inside&.dungeon? ? [ { "label" => "Into #{inside.name}", "move" => { "location" => inside.id, "enter" => true } } ] : []
      # The place's own things to do first, then the ways out, then its inn,
      # temple and guild, or camp (Location::Town#services_for, Campaign::Services).
      own, services = pastimes_here.partition { |way| way["service"].nil? }
      travel_ticks = ticking_on("travel")
      roads = current_node.edges.includes(:from_node, :to_node).reject(&:blocked?).map do |edge|
        { "label" => way_along(edge), "move" => { "edge" => edge.id },
          "note" => ("ticks #{travel_ticks.to_sentence}" if travel_ticks.any?),
          "warn" => ("The road to #{edge.other_end(current_node).name} is dangerous: the party may meet something on it." if edge.state == "dangerous") }.compact
      end
      own + way_in + roads + services.map { |way| way.except("service") }
    else
      []
    end
  end

  # The open "Where next?", or a new one. Refused while the table is
  # deciding something else, or when there's nowhere to go. What's on
  # the ballot (scope): the ways on from here that fit the controls
  # (Campaign::Controls#ways_offered: the roads in travel, the things to
  # do here in doing, all of them when nothing is called), every place on
  # a map the party can reach by road, or places the GM names (places:
  # nodes); settling it takes the party there, however many roads away
  # (Travelling#travel_to!).
  def ask_where_next!(scope: "here", map: nil, places: nil)
    choice = open_choice
    return choice if choice&.where_next? && scope == "here"
    raise Refusal, "The table is deciding something else first" if choice && !choice.where_next?
    refuse_while_encounter_waits!

    ways = case scope
    when "map" then ways_across(map || party_map || root_map)
    when "places" then ways_to(Array(places))
    else controls == "talk" ? ways_on : ways_offered
    end
    raise Refusal, "There's nowhere to go from here" if ways.empty?
    raise Refusal, "That's too many places for one vote (#{Message::Choice::MAX_MOVES} at most)" if ways.size > Message::Choice::MAX_MOVES

    choice&.destroy!
    options = ways.map { |way| way["label"] } + [ STAY ]
    Message.choice(self, options: options).tap do |ask|
      # The ways are in the vote's panel; the log says only that it's asked.
      ask.body = "Where next? #{options.size} ways to choose from."
      ask.data = { "moves" => ways.to_h { |way| [ way["label"], way["move"] ] }, "scope" => scope }
      ask.save!
    end
  end

  # Every place the players know on a map that a road leads to from here, as ways.
  def ways_across(map)
    return [] unless current_node

    ways_to(map.map_nodes.where(visible: true).where.not(id: current_node.id).order(:name))
  end

  # The places named, as ways, when a road leads there: "To Walse (2 days)".
  def ways_to(nodes)
    return [] unless current_node && !dungeon_in_progress

    nodes.filter_map do |node|
      next if node.id == current_node.id

      legs = route_to(node) or next
      time = legs.sum { |leg| leg.duration.to_i }
      risky = legs.any? { |leg| leg.state == "dangerous" }
      { "label" => "To #{node.name}#{" (#{journey_length(time)})" if time.positive?}#{' (by a dangerous road)' if risky}",
        "move" => { "to" => node.id }, "warn" => ("The road to #{node.name} is dangerous: the party may meet something on it." if risky) }.compact
    end
  end

  # The GM takes a way straight off (no vote): the move is made, and any
  # vote on it is over.
  def take_way!(label)
    refuse_while_encounter_waits!
    way = ways_on.find { |w| w["label"] == label } or raise Refusal, "That isn't a way on from here"
    make_move!(way["move"])
  end

  # What there is to do where the party is, this part of the day.
  def pastimes_here
    return [] unless current_node && !dungeon_in_progress

    rest_ticks = ticking_on("rest")
    current_node.pastimes.select { |pastime| pastime.open?(almanac, day, period) }.map do |pastime|
      { "label" => pastime_label(pastime), "move" => { "node" => current_node.id, "pastime" => pastime.name }, "service" => pastime.service,
        "note" => way_note(pastime, rest_ticks),
        "warn" => ("The night passes: it's #{almanac.periods.first} when they're done." if pastime.rest?) }.compact
    end
  end

  # What a thing to do sets off, said before it's chosen (docs/DESIGN.md,
  # "Motion with meaning"): its outcomes, and the clocks a night ticks.
  def way_note(pastime, rest_ticks = ticking_on("rest"))
    parts = pastime.outcomes.map { |outcome| outcome.kind == "rest" ? "the night passes" : outcome.describe(world).downcase_first }
    parts << "ticks #{rest_ticks.to_sentence}" if pastime.rest? && rest_ticks.any?
    parts.join(" · ").presence
  end

  # The names of the clocks an event would tick now, for the ways' notes.
  def ticking_on(event)
    clocks.where(stopped_at: nil).reject(&:full?).select { |clock| clock.ticks_on?(event) }.map(&:name)
  end

  # Parts of a day as the table hears them: "a part of a day", "2 days", "a day and 2 parts".
  def journey_length(parts)
    a_day = almanac.periods.size
    days, rest = parts.divmod(a_day)
    words = []
    words << (days == 1 ? "a day" : "#{days} days") if days.positive?
    words << (rest == 1 ? (days.positive? ? "a part" : "a part of a day") : "#{rest} parts#{' of a day' unless days.positive?}") if rest.positive?
    words.join(" and ")
  end

  # How the table sees a road from here: "To Greymere (by a dangerous road)".
  def way_along(edge)
    "To #{edge.other_end(current_node).name}#{' (by a dangerous road)' if edge.state == 'dangerous'}"
  end

  # How the table sees a thing to do now: "Rooms at the Gull (50 gil, overnight)".
  def pastime_label(pastime)
    pastime.label(almanac, period, cost: (money(pastime.price) if pastime.price.positive?))
  end

  # The party does something here: it pays, the table hears it, what it
  # does happens (Outcome), and the time goes by (a rest takes the night).
  # Returns the line the table heard.
  def spend_time!(node, name)
    pastime = node.pastimes.find { |p| p.name == name } or raise Refusal, "There's no #{name} at #{node.name}"
    raise Refusal, "The party isn't at #{node.name}" unless current_node == node
    raise Refusal, "#{pastime.name} isn't something to do now (#{period})" unless pastime.open?(almanac, day, period)
    raise Refusal, "Not while a battle is on" if battle_on?

    pastime.outcomes.each { |outcome| outcome.can_happen!(self) }
    heard = nil
    transaction do
      reload
      raise Refusal, "The party has #{money(gil)}; #{pastime.name} costs #{money(pastime.price)}" if pastime.price > gil

      decrement!(:gil, pastime.price) if pastime.price.positive?
      heard = narrate("#{node.name}: #{pastime.name}#{" (#{money(pastime.price)})" if pastime.price.positive?}.")
      messages.create!(body: pastime.line) if pastime.line
      pastime.outcomes.each do |outcome|
        said = outcome.apply!(self, by: "The party")
        narrate(said) if said
      end
      node.location.meet_wish!(pastime.wish) if pastime.wish
      next if pastime.rest? || pastime.takes.zero?

      spent_time!(pastime.takes) # paid at the next rest (Campaign::Payoffs)
      pass_time!(pastime.takes)
    end
    table_changed # the purse, and whatever the outcome touched
    heard.body
  end

  # Make a way's move: travel a path (or all the way to a place), step into
  # a room, or spend time here.
  def make_move!(move)
    if move["pastime"]
      spend_time!(map_nodes.find(move["node"]), move["pastime"])
    elsif move["to"]
      travel_to!(map_nodes.find(move["to"]))
    elsif move["edge"]
      travel!(map_edges.find(move["edge"]))
    elsif move["leave"]
      locations.find(move["location"]).leave!
      narrate("The party comes back out of #{locations.find(move['location']).name}.", data: Campaign::MOVED)
    elsif move["enter"]
      locations.find(move["location"]).enter!
    elsif move["room"]
      locations.find(move["location"]).move_to!(move["room"])
    elsif move["recover"]
      recover!(move["recover"])
    end
  end

  # A vote on where to go that the party has moved on from, by some other
  # way: taken off the table, since its ways are gone.
  def drop_stale_where_next!
    stale = open_choice
    return unless stale&.where_next?

    stale.destroy!
    stale.broadcast_choice
  end

  # A rolled encounter is the table's now: the GM fights it or waves it off before the party goes on.
  def refuse_while_encounter_waits!
    raise Refusal, "Something waits on the road: the GM calls it (fight, or wave it off) first" if pending_encounter.present?
  end

  # Doors on from here the party can't open yet: shown, so they know what
  # to look for, but not a way anyone can vote for. ["Iron door (needs the Rusty key)"]
  def locked_ways
    dungeon = dungeon_in_progress or return []
    here = dungeon.progress["current"]
    dungeon.neighbours(here).filter_map do |key|
      path = dungeon.path_between(here, key)
      "#{path['lock']['name']} (needs #{path['lock']['key_name']})" if dungeon.locked?(path) && !dungeon.has_key?(path["lock"])
    end
  end

  private

  def dungeon_ways(dungeon)
    here = dungeon.progress["current"]
    ways = dungeon.neighbours(here).filter_map do |key|
      path = dungeon.path_between(here, key)
      [ key, path ] unless dungeon.locked?(path) && !dungeon.has_key?(path["lock"])
    end
    way_out = here == dungeon.view["entrance"] ? [ { "label" => "Leave #{dungeon.name}", "move" => { "location" => dungeon.id, "leave" => true } } ] : []
    unseen = ways.map(&:first).reject { |key| dungeon.seen_by_players?(key) }
    ways.map do |key, path|
      label = if dungeon.seen_by_players?(key) then dungeon.room(key)["name"]
      elsif unseen.one? then "An unexplored way"
      else "An unexplored way (#{unseen.index(key) + 1})"
      end
      if path&.dig("cost") && !dungeon.paid?(path)
        toll = dungeon.toll_of(path)
        label += toll ? " (costs #{toll.describe(self)})" : " (costly)"
      end
      { "label" => label, "move" => { "location" => dungeon.id, "room" => key } }
    end + way_out
  end
end
