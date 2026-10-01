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
      roads = current_node.edges.includes(:from_node, :to_node).reject(&:blocked?).map do |edge|
        { "label" => way_along(edge), "move" => { "edge" => edge.id },
          "warn" => ("The road to #{edge.other_end(current_node).name} is dangerous: the party may meet something on it." if edge.state == "dangerous") }.compact
      end
      own + way_in + roads + services.map { |way| way.except("service") }
    else
      []
    end
  end

  # The open "Where next?", or a new one. Refused while the table is
  # deciding something else, or when there's nowhere to go.
  def ask_where_next!
    choice = open_choice
    return choice if choice&.where_next?
    raise Refusal, "The table is deciding something else first" if choice

    ways = ways_on
    raise Refusal, "There's nowhere to go from here" if ways.empty?

    options = ways.map { |way| way["label"] } + [ STAY ]
    Message.choice(self, options: options).tap do |ask|
      # The ways are in the vote's panel; the log says only that it's asked.
      ask.body = "Where next? #{options.size} ways to choose from."
      ask.data = { "moves" => ways.to_h { |way| [ way["label"], way["move"] ] } }
      ask.save!
    end
  end

  # The GM takes a way straight off (no vote): the move is made, and any
  # vote on it is over.
  def take_way!(label)
    way = ways_on.find { |w| w["label"] == label } or raise Refusal, "That isn't a way on from here"
    make_move!(way["move"])
  end

  # What there is to do where the party is, this part of the day.
  def pastimes_here
    return [] unless current_node && !dungeon_in_progress

    current_node.pastimes.select { |pastime| pastime.open?(almanac, day, period) }.map do |pastime|
      { "label" => pastime_label(pastime), "move" => { "node" => current_node.id, "pastime" => pastime.name }, "service" => pastime.service,
        "warn" => ("The night passes: it's #{almanac.periods.first} when they're done." if pastime.rest?) }.compact
    end
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
  def spend_time!(node, name)
    pastime = node.pastimes.find { |p| p.name == name } or raise Refusal, "There's no #{name} at #{node.name}"
    raise Refusal, "The party isn't at #{node.name}" unless current_node == node
    raise Refusal, "#{pastime.name} isn't something to do now (#{period})" unless pastime.open?(almanac, day, period)
    raise Refusal, "Not while a battle is on" if battle_on?

    pastime.outcomes.each { |outcome| outcome.can_happen!(self) }
    transaction do
      reload
      raise Refusal, "The party has #{money(gil)}; #{pastime.name} costs #{money(pastime.price)}" if pastime.price > gil

      decrement!(:gil, pastime.price) if pastime.price.positive?
      narrate("#{node.name}: #{pastime.name}#{" (#{money(pastime.price)})" if pastime.price.positive?}.")
      messages.create!(body: pastime.line) if pastime.line
      pastime.outcomes.each do |outcome|
        said = outcome.apply!(self, by: "The party")
        narrate(said) if said
      end
      next if pastime.rest? || pastime.takes.zero?

      spent_time!(pastime.takes) # paid at the next rest (Campaign::Payoffs)
      pass_time!(pastime.takes)
    end
    table_changed # the purse, and whatever the outcome touched
  end

  # Make a way's move: travel a path, step into a room, or spend time here.
  def make_move!(move)
    if move["pastime"]
      spend_time!(map_nodes.find(move["node"]), move["pastime"])
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
      label += " (costly)" if path&.dig("cost")
      { "label" => label, "move" => { "location" => dungeon.id, "room" => key } }
    end + way_out
  end
end
