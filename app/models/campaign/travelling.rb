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
        self.rng, rolled = Pointcrawl::Encounters.roll(rng, edge.encounter_table.entries, edge.state)
      end
      self.safe_road = false if safe
      destination.update!(visible: true)
      origin.location&.leave!
      self.current_node = destination
      self.pending_encounter = rolled && { "table" => edge.encounter_table.name, "monsters" => rolled, "terrain" => edge.encounter_table.terrain_type }
      # A place in a mode can have trouble waiting.
      if !rolled && (trouble = destination.location&.encounter_table_for_mode)
        self.rng, rolled = Pointcrawl::Encounters.roll(rng, trouble.entries, "dangerous")
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
    end
    broadcast_map
    rolled
  end

  # GM: put the party somewhere directly (and reveal it).
  def place_party!(node)
    transaction do
      node.update!(visible: true)
      current_node&.location&.leave! unless current_node == node
      update!(current_node: node)
      narrate("The party is at #{node.name}.")
      hear_rumours!(node)
    end
    broadcast_map
  end

  def start_pending_encounter!(input_seconds: nil)
    encounter = pending_encounter or raise Refusal, "No encounter is waiting"
    standing = characters.order(:created_at).select(&:conscious?)
    raise Refusal, "Nobody is standing to fight" if standing.empty?

    battle = BattleRecord.start!(campaign: self, characters: standing, name: encounter["table"],
                                 encounter: encounter["monsters"], input_seconds: input_seconds, boss: encounter["boss"] || false,
                                 terrain: encounter["terrain"])
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

  # Re-render the map for each audience. Players get a separately rendered
  # map without hidden places, on their own stream, so a hidden node never
  # reaches their browser.
  def broadcast_map
    { false => :map, true => :map_gm }.each do |gm, stream|
      broadcast_replace_to self, stream, target: "map_canvas", partial: "maps/canvas", locals: { campaign: self, gm: gm }
    end
  end

  # The dungeon the party is inside right now, if any.
  def dungeon_in_progress
    location = current_node&.location
    location if location&.dungeon? && location.progress["current"]
  end
end
