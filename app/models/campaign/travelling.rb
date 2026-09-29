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
      origin.location&.leave!
      self.current_node = destination
      self.pending_encounter = rolled && { "table" => edge.encounter_table.name, "monsters" => rolled, "terrain" => edge.encounter_table.terrain_type }
      # A place in a mode can have trouble waiting.
      if !rolled && (trouble = destination.location&.encounter_table_for_mode)
        rolled = roll_with { |state| Pointcrawl::Encounters.roll(state, trouble.entries, "dangerous") }
        self.pending_encounter = rolled && { "table" => "#{destination.name}: #{destination.location.current_mode['name']}", "monsters" => rolled,
                                             "terrain" => trouble.terrain_type }
      end
      save!

      narrate("The party travels from #{origin.name} to #{destination.name}.")
      messages.create!(body: edge.travel_event) if edge.travel_event
      narrate("The way is safe: nothing troubles the party on the road.") if safe
      narrate("Encounter! #{describe_encounter(rolled)}.") if rolled
      tick_clocks!("travel")
      pass_time!(edge.duration, announce: :new_day)
      hear_rumours!(destination)
      drop_stale_where_next!
    end
    broadcast_map
    rolled
  end

  # What a new party has to spend.
  STARTING_GIL = 150

  # A new campaign: the party starts in the setting's first town it knows
  # that has a road out (Atlas), with money and the starting bag, and hears
  # what people there are saying (which may put somewhere on the map).
  def set_out!
    transaction do
      pack_starting_bag!
      increment!(:gil, STARTING_GIL)
      start = starting_town
      next unless start && current_node.nil?

      update!(current_node: start)
      hear_rumours!(start)
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
      current_node&.location&.leave! unless current_node == node
      update!(current_node: node)
      narrate("The party is at #{node.name}.")
      hear_rumours!(node)
      drop_stale_where_next!
    end
    broadcast_map
  end

  # The most a boss's prelude says before the fight.
  PRELUDE_LINES = 8

  # prelude: lines said in the dialogue box first (a boss's entrance); the
  # battle's pull waits for them (stage.js).
  def start_pending_encounter!(input_seconds: nil, prelude: [])
    encounter = pending_encounter or raise Refusal, "No encounter is waiting"
    standing = characters.order(:created_at).select(&:conscious?)
    raise Refusal, "Nobody is standing to fight" if standing.empty?

    prelude.first(PRELUDE_LINES).each { |line| messages.create!(body: line.to_s.first(500)) }

    battle = BattleRecord.start!(campaign: self, characters: standing, name: encounter["table"],
                                 encounter: encounter["monsters"], input_seconds: input_seconds, boss: encounter["boss"] || false,
                                 terrain: encounter["terrain"], names: encounter.fetch("names", {}))
    update!(pending_encounter: nil)
    battle
  end

  def wave_off_encounter!
    return unless pending_encounter

    update!(pending_encounter: nil)
    narrate("The GM waves off the encounter.")
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
