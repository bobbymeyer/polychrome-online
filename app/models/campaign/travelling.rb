# frozen_string_literal: true

# The party on the pointcrawl map (§7): travelling along its paths, being
# put somewhere by the GM, and the encounters waiting on the road.
module Campaign::Travelling
  extend ActiveSupport::Concern

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
      self.free_rooms_node_id = nil # the town's thanks were for while the party was there
      self.pending_encounter = rolled && { "table" => edge.encounter_table.name, "monsters" => rolled, "terrain" => edge.encounter_table.terrain_type }
      # A place in a mode (as it will be when the party gets there) can have trouble waiting.
      arrival_period, days_on = almanac.later(period, edge.duration.to_i)
      if !rolled && (troubled = destination.location&.troubled_by(day: day + days_on, period: arrival_period))
        trouble = troubled.encounter_table
        rolled = roll_with { |state| Pointcrawl::Encounters.roll(state, trouble.entries, "dangerous") }
        self.pending_encounter = rolled && { "table" => "#{destination.name}: #{troubled.name}", "monsters" => rolled, "terrain" => trouble.terrain_type }
      end
      save!

      narrate("The party travels from #{origin.name} to #{destination.name}.")
      messages.create!(body: edge.travel_event) if edge.travel_event
      narrate("The way is safe: nothing troubles the party on the road.") if safe
      narrate("Encounter! #{describe_encounter(rolled)}.") if rolled
      happen!("travel")
      @arriving = destination # what it's like there is said once, on arrival
      pass_time!(edge.duration, announce: :new_day)
      @arriving = nil
      how_it_is_here!(destination)
      destination.location&.remember!
      hear_rumours!(destination)
      welcome_back!(destination)
      drop_stale_where_next!
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
    map_edges.pluck(:from_node_id, :to_node_id, :state).map { |from, to, state| { "from" => from, "to" => to, "state" => state } }
  end

  # GM: put the party somewhere directly (and reveal it).
  def place_party!(node)
    transaction do
      node.update!(visible: true)
      moved = current_node != node
      current_node&.location&.leave! if moved
      update!(current_node: node, free_rooms_node_id: (free_rooms_node_id if node == current_node))
      narrate("The party is at #{node.name}.")
      how_it_is_here!(node) if moved
      node.location&.remember!
      hear_rumours!(node)
      welcome_back!(node)
      drop_stale_where_next!
    end
  end

  # The most a boss's prelude says before the fight.
  PRELUDE_LINES = 8

  # prelude: lines said in the dialogue box first (a boss's entrance); the
  # battle's pull waits for them (stage.js).
  def start_pending_encounter!(input_seconds: nil, prelude: [])
    encounter = pending_encounter or raise Refusal, "No encounter is waiting"
    party = characters.order(:created_at).to_a
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
                                 terrain: encounter["terrain"], names: encounter.fetch("names", {}),
                                 antagonists: npcs.where(id: encounter.fetch("antagonists", [])).to_a)
    update!(pending_encounter: nil)
    battle
  end

  # A boss waved off isn't gone: it goes back to its room, to wait for the
  # party (a road's or a room's ordinary fight just doesn't happen).
  def wave_off_encounter!
    waiting = pending_encounter or return

    transaction do
      update!(pending_encounter: nil)
      if waiting["boss"] && waiting["location"] && (lair = locations.find_by(id: waiting["location"]))
        lair.reopen_room!(waiting["room"])
        narrate("The GM holds the fight back: it waits in #{lair.room(waiting['room'])&.dig('name') || lair.name}.")
      else
        narrate("The GM waves off the encounter.")
      end
    end
  end

  def describe_encounter(monsters)
    names = world.monsters.where(slug: monsters.keys).index_by(&:slug)
    monsters.map { |slug, count| "#{count} × #{names[slug]&.name || slug}" }.to_sentence
  end

  # The dungeon the party is inside right now, if any.
  def dungeon_in_progress
    location = current_node&.location
    location if location&.dungeon? && location.progress["current"]
  end
end
