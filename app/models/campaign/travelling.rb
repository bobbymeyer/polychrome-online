# frozen_string_literal: true

# The party on the pointcrawl map (§7): travelling along its paths, being
# put somewhere by the GM, and the encounters waiting on the road.
module Campaign::Travelling
  extend ActiveSupport::Concern

  # Marks a line that says the party moved (a road, a room, a door): what
  # was said before it was said somewhere else (the table's dialogue box
  # doesn't keep it up).
  MOVED = { "moved" => true }.freeze

  # Move the party along an edge from where it stands. Arriving reveals the
  # destination. If the edge has an encounter table, roll on it with the
  # campaign's RNG; a hit waits as the pending encounter for the GM to start
  # or wave off. Everything is announced at the table.
  def travel!(edge)
    rolled = nil
    with_lock do
      raise Refusal, "The party isn't on the map" unless current_node
      raise Refusal, "That path doesn't start here" unless edge.touches?(current_node)
      raise Refusal, "That path is blocked" if edge.blocked?

      origin = current_node
      destination = edge.other_end(origin)
      # A field ability found a way through (FieldUse "safe_road"): the next
      # dangerous path rolls nothing.
      safe = edge.encounter_table && safe_road
      if edge.encounter_table && !safe
        rolled = roll_with { |state| Pointcrawl::Encounters.roll(state, edge.encounter_table.entries, edge.state) }
      end
      self.safe_road = false if safe
      destination.update!(visible: true)
      hear_rumours!(origin) # what people were saying there, heard on the way out
      origin.location&.leave!
      self.current_node = destination
      self.pending_encounter = rolled && fight(edge.encounter_table.name, rolled, terrain: edge.encounter_table.terrain_type)
      # A place in a mode (as it will be when the party gets there) can have trouble waiting.
      arrival_period, days_on = almanac.later(period, edge.duration.to_i)
      if !rolled && (troubled = destination.troubled_by(day: day + days_on, period: arrival_period))
        trouble = troubled.encounter_table
        rolled = roll_with { |state| Pointcrawl::Encounters.roll(state, trouble.entries, "dangerous") }
        self.pending_encounter = rolled && fight("#{destination.name}: #{troubled.name}", rolled, terrain: trouble.terrain_type)
      end
      save!

      # The arrival is a card over the table (campaigns/tables/_cards): the place's name, its kind, its face now.
      narrate("The party travels from #{origin.name} to #{destination.name}.", cue: "arrival",
              data: MOVED.merge("place" => destination.name, "kind" => destination.kind.humanize,
                                "modes" => destination.modes_on.map(&:name).join(" · "), "line" => destination.description.to_s.truncate(160)))
      messages.create!(body: edge.travel_event) if edge.travel_event
      narrate("The way is safe: nothing troubles the party on the road.") if safe
      narrate("Encounter! #{describe_encounter(rolled)}.") if rolled
      happen!("travel")
      @arriving = destination # what it's like there is said once, on arrival
      pass_time!(edge.duration, announce: :new_day)
      @arriving = nil
      arrive_at!(destination)
    end
    rolled
  end

  # What a new party has to spend.
  STARTING_GIL = 150

  # A new campaign begins. From the setting (unless the GM starts from
  # nothing): its places and people (Atlas) and its trouble, the fronts,
  # dealt in. Then the party sets out, from the first town it knows with a
  # road out, with money and the starting bag. What people there are saying
  # (which may put somewhere on the map) is heard that night, after the GM's
  # opening, not before it.
  def set_out!(from_the_setting: true)
    transaction do
      if from_the_setting
        Atlas.new(self).bring_in_all!
        WorldFront.undealt_in(self).each { |front| front.deal!(self) }
      end
      pack_starting_bag!
      increment!(:gil, STARTING_GIL)
      start = starting_town
      next unless start && current_node.nil?

      # What people there are saying waits for the first night (or the next
      # place the party reaches): the GM's opening scene comes first.
      update!(current_node: start)
    end
  end

  def starting_town
    towns = map_nodes.where(visible: true, kind: "town").order(Arel.sql("world_place_id IS NULL"), :world_place_id, :id).to_a
    roads = map_edges.pluck(:from_node_id, :to_node_id).flatten.to_set
    towns.find { |town| roads.include?(town.id) } || towns.first
  end

  # The known town nearest a place by road (the place itself if it's one),
  # or nil if no open road leads to one.
  def nearest_town(from, **options)
    nearest(from, map_nodes.where(visible: true, kind: "town"), **options)
  end

  # The nearest by road of some places (the place itself if it's one of
  # them), or nil. Blocked roads don't count unless asked: talk gets over a
  # snowed-in pass, people don't (Pointcrawl::Roads).
  def nearest(from, among, through_blocked: false, roads: self.roads)
    return unless from

    roads = Pointcrawl::Roads.passable(roads) unless through_blocked
    found = Pointcrawl::Roads.nearest(roads, from.id, among.pluck(:id))
    found && map_nodes.find(found)
  end

  # The map's roads as plain data (Pointcrawl::Roads).
  def roads
    map_edges.pluck(:id, :from_node_id, :to_node_id, :state, :duration).map do |id, from, to, state, duration|
      { "id" => id, "from" => from, "to" => to, "state" => state, "duration" => duration }
    end
  end

  # The roads from where the party is to a place, in order (MapEdge), or
  # nil when no open road leads there (Pointcrawl::Roads.route).
  def route_to(node)
    return unless current_node

    walked = Pointcrawl::Roads.route(roads, current_node.id, node.id) or return
    by_id = map_edges.where(id: walked.map { |road| road["id"] }).index_by(&:id)
    walked.map { |road| by_id.fetch(road["id"]) }
  end

  # Travel to a place anywhere on the roads, one road after another (a
  # "Where next?" across a map): the journey stops where something waits
  # on the road, for the GM to call, and the party goes on from there by
  # another ask. Returns the place reached.
  def travel_to!(node)
    refuse_while_encounter_waits!
    raise Refusal, "The party is already at #{node.name}" if current_node == node

    legs = route_to(node) or raise Refusal, "No open road leads to #{node.name} from here"
    legs.each do |edge|
      travel!(edge)
      break if pending_encounter.present?
    end
    reload.current_node
  end

  # GM: put the party somewhere directly (and reveal it).
  def place_party!(node)
    transaction do
      node.update!(visible: true)
      moved = current_node != node
      current_node&.location&.leave! if moved
      update!(current_node: node)
      narrate("The party is at #{node.name}.", data: MOVED)
      arrive_at!(node, moved: moved)
    end
  end

  # A fight waiting for the GM to call or wave off, however it came: on a
  # road, as trouble at a place, in a dungeon's room, from a villain at home,
  # or as an outcome. name: what the table sees it as; monsters: { slug =>
  # count }; the rest as the battle takes it (#start_pending_encounter!):
  # terrain, names, antagonists, and for a room's, location, room and prelude.
  def waylay!(name, monsters, **details)
    update!(pending_encounter: fight(name, monsters, **details))
  end

  # The most a boss's prelude says before the fight.
  PRELUDE_LINES = 8

  # prelude: lines said in the dialogue box first (a boss's entrance); the
  # battle's pull waits for them (stage.js).
  def start_pending_encounter!(input_seconds: nil, prelude: [])
    encounter = pending_encounter or raise Refusal, "No encounter is waiting"
    party = characters.reload.to_a # as they are now, not as this instance last saw them
    raise Refusal, "Nobody is standing to fight" if party.none?(&:conscious?)

    # Read as a scene's lines are: "Kurosaki (sad): …" is Kurosaki's, sadly.
    cast = npcs.to_a
    prelude.first(PRELUDE_LINES).each do |raw|
      line = Scene.read_line(raw.to_s.strip.first(500), cast)
      line = { "text" => raw.to_s.strip.first(500) } if line["problem"] # someone not in the cast: said as written
      messages.create!(speaker: line["speaker"], expression: line["expression"], body: line["text"])
    end

    # The fallen come too, down: their players watch, and a raise brings them in.
    battle = BattleRecord.start!(campaign: self, characters: party, name: encounter["table"],
                                 encounter: encounter["monsters"], input_seconds: input_seconds, boss: encounter["boss"] || false,
                                 terrain: encounter["terrain"], names: encounter.fetch("names", {}), room: encounter["room"],
                                 antagonists: npcs.where(id: encounter.fetch("antagonists", [])).to_a,
                                 escapable: !encounter["boss"]) # a boss fight is fought (the Fight panel has its own say)
    update!(pending_encounter: nil)
    battle
  end

  # A boss waved off isn't gone: it stays in its room, waiting for the party
  # (a road's fight just doesn't happen, and a room's ordinary fight is
  # dealt with: Location::Exploration).
  def wave_off_encounter!
    waiting = pending_encounter or return

    transaction do
      update!(pending_encounter: nil)
      lair = waiting["location"] && waiting["room"] && locations.find_by(id: waiting["location"])
      if lair && waiting["boss"]
        narrate("The GM holds the fight back: it waits in #{lair.room(waiting['room'])&.dig('name') || lair.name}.")
      else
        lair&.resolve!(waiting["room"])
        narrate("The GM waves off the encounter.")
      end
    end
  end

  def describe_encounter(monsters)
    names = world.monsters.where(slug: monsters.keys).index_by(&:slug)
    monsters.map { |slug, count| "#{count} × #{names[slug]&.name || slug}" }.to_sentence
  end

  # Who waits in the rolled encounter: its antagonists by name, then its
  # monsters ("Garland and 2 × Goblin").
  def encounter_foes(encounter = pending_encounter)
    return [] if encounter.blank?

    names = npcs.where(id: encounter.fetch("antagonists", [])).map(&:name)
    names << describe_encounter(encounter["monsters"]) if encounter["monsters"].present?
    names
  end

  # The dungeon the party is inside right now, if any.
  def dungeon_in_progress
    location = current_node&.location
    location if location&.dungeon? && location.current_room_key
  end

  private

  # The party is at a place (the campaign saved there): what it's like
  # there, what happens on arriving (Campaign::Happenings), what people are
  # saying and how the place takes to them (Campaign::Deeds), and the vote
  # on where next is over. moved: whether they weren't there already (put
  # where they stand, only the place's news is heard again).
  def arrive_at!(node, moved: true)
    how_it_is_here!(node) if moved
    node.location&.remember!
    happen!("arrive", at: node) if moved
    hear_rumours!(node) # a step (a door, a platform) passes no time, so nothing heard it on the way (Happenings "hours")
    welcome_back!(node)
    drop_stale_where_next!
  end

  # A waiting fight, as it's kept (#waylay!).
  def fight(name, monsters, boss: false, **details)
    { "table" => name, "monsters" => monsters, "boss" => (true if boss) }.merge(details.transform_keys(&:to_s)).compact
  end
end
