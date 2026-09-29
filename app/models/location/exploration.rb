# frozen_string_literal: true

# A dungeon is a nested pointcrawl: #progress records the party's room,
# what they've seen and dealt with, and the keys they've found. Moving into
# a room plays its decision at the table.
module Location::Exploration
  extend ActiveSupport::Concern

  def room(key)
    view.fetch("rooms", []).find { |r| r["key"] == key }
  end

  def current_room
    room(progress["current"])
  end

  def visited
    progress.fetch("visited", [])
  end

  def resolved?(key)
    progress.fetch("resolved", []).include?(key)
  end

  # --- locks and keys ----------------------------------------------------------

  # Lock ids whose keys the party has found here.
  def keys_found
    progress.fetch("keys", [])
  end

  def unlocked?(lock)
    progress.fetch("unlocked", []).include?(lock["id"])
  end

  # A path that's locked and still shut.
  def locked?(path)
    path&.dig("lock") && !unlocked?(path["lock"])
  end

  def has_key?(lock)
    keys_found.include?(lock["id"])
  end

  # What the party carries: the keys found and not yet used.
  def keys_in_hand
    view.fetch("paths", []).filter_map { |p| p["lock"] }.uniq { |l| l["id"] }
        .select { |lock| has_key?(lock) && !unlocked?(lock) }
  end

  def neighbours(key)
    view.fetch("paths", []).filter_map do |path|
      (path["to"] if path["from"] == key) || (path["from"] if path["to"] == key)
    end
  end

  def path_between(a, b)
    view.fetch("paths", []).find { |p| [ p["from"], p["to"] ].sort == [ a, b ].sort }
  end

  # Players see rooms they've been in, and the exits leading out of them.
  def seen_by_players?(key)
    visited.include?(key) || visited.any? { |v| neighbours(v).include?(key) }
  end

  # Only the place the party stands on the map can be explored.
  def party_here?
    map_node&.party_here? || false
  end

  # The party went back out onto the map: next time, they come in at the entrance.
  def leave!
    walk_away_from_fight!
    update!(progress: progress.except("current")) if progress["current"]
  end

  def enter!
    move_to!(view["entrance"], from: nil)
  end

  # Move the party to a room next to the one they're in, and play out its
  # decision at the table: an event is narrated; an encounter or the boss
  # waits for the GM to fight or wave off (like on the map); treasure waits
  # to be handed over; a fork shows its visible cost.
  def move_to!(key, from: progress["current"])
    raise Refusal, "The party isn't at #{name}. Take them there on the map first." unless party_here?

    target = room(key) or raise Refusal, "No such room"
    raise Refusal, "That room isn't next to this one" if from && !neighbours(from).include?(key)

    path = from && path_between(from, key)
    lock = path && locked?(path) ? path["lock"] : nil
    raise Refusal, "#{lock['name']} bars the way. It needs #{lock['key_name']}." if lock && !has_key?(lock)

    transaction do
      walk_away_from_fight!(to: key)
      if lock
        update!(progress: progress.merge("unlocked" => progress.fetch("unlocked", []) | [ lock["id"] ]))
        campaign.narrate("#{name}: #{lock['key_name']} opens #{lock['name']}. The way is clear.", cue: "door")
      end
      update!(progress: progress.merge("current" => key, "visited" => (visited | [ key ])))
      campaign.narrate("#{name}: the party enters #{target['name']}.")
      campaign.narrate("The cost of that way: #{path['cost']}") if path&.dig("cost")
      announce(target) unless resolved?(key)
      campaign.drop_stale_where_next!
    end
  end

  # Hand a room's treasure to the party (once).
  def take_treasure!(key)
    target = room(key)
    raise Refusal, "No treasure there" unless target && target["decision"]["kind"] == "treasure" && !resolved?(key)

    decision = target["decision"]
    item = campaign.world.items.find_by(slug: decision["item"]) if decision["item"]
    line = "Found #{describe_treasure(decision)} in #{target['name']}.#{" #{who_can_use(item)}" if item&.equipment?}"
    transaction do
      campaign.add_item!(item) if item
      campaign.increment!(:gil, decision["gil"].to_i) if decision["gil"]
      resolve!(key)
      campaign.narrate(line, cue: "treasure")
    end
    campaign.table_changed # the table's "Take it" goes
    line
  end

  # Gear found says who it's for: a sword nobody can swing is still worth
  # knowing about (a job change away, or a shop's price).
  def who_can_use(item)
    party = campaign.characters.includes(:job).select { |c| c.job.equips?(item) }.map(&:name)
    return "#{party.to_sentence} can use it." if party.any?

    jobs = campaign.available_jobs.select { |j| j.equips?(item) }.map(&:name)
    jobs.any? ? "Nobody can use it as they are; a #{jobs.to_sentence(last_word_connector: ' or ', two_words_connector: ' or ')} could." : "Nobody here can use it, but it will sell."
  end

  # "Potion", "150 gil", "150 gil, in the Vell signet (made for Aldo Vell)".
  def describe_treasure(decision)
    found = decision["gil"] ? "#{decision['gil']} gil" : campaign.world.items.find_by(slug: decision["item"])&.name || decision["item"]
    heirloom = decision["heirloom"]
    return found unless heirloom

    made = [ ("made by #{heirloom['maker']}" if heirloom["maker"]), ("for #{heirloom['made_for']}" if heirloom["made_for"]) ].compact.join(" ")
    "#{found}, with #{heirloom['name']}#{" (#{made})" if made.present?}"
  end

  def resolve!(key)
    update!(progress: progress.merge("resolved" => (progress.fetch("resolved", []) | [ key ])))
  end

  private

  # The party walked on without fighting what waits in a room here: it
  # stays in its room for when they come back, and doesn't follow them.
  def walk_away_from_fight!(to: nil)
    waiting = campaign.pending_encounter
    return unless waiting && waiting["location"] == id && waiting["room"] != to

    update!(progress: progress.merge("resolved" => progress.fetch("resolved", []) - [ waiting["room"] ]))
    campaign.update!(pending_encounter: nil)
  end

  def announce(target)
    decision = target["decision"]
    case decision["kind"]
    when "event"
      campaign.messages.create!(body: decision["text"])
      resolve!(target["key"])
    when "encounter", "boss"
      label = decision["kind"] == "boss" ? "The master of #{name}" : "#{name}: #{target['name']}"
      # Who the place's past says waits here (Generators::Provenance) is who
      # the table fights: the strongest of them takes that name.
      who = decision["who"].to_s.split(",").first.presence
      leader = who && campaign.world.monsters.where(slug: decision["monsters"].keys).order(level: :desc).first
      boss = decision["kind"] == "boss"
      campaign.update!(pending_encounter: { "table" => label, "monsters" => decision["monsters"], "boss" => boss,
                                            "terrain" => location_template.encounter_table&.terrain_type,
                                            "names" => ({ leader.slug => who } if leader),
                                            "location" => id, "room" => target["key"],
                                            "prelude" => (boss_prelude(target, who) if boss) }.compact)
      campaign.narrate("#{decision['kind'] == 'boss' ? 'Boss' : 'Encounter'}! #{"#{who}: " if leader}#{campaign.describe_encounter(decision['monsters'])}.")
      resolve!(target["key"])
    when "treasure"
      campaign.narrate("There is treasure in #{target['name']}.")
    when "fork"
      campaign.narrate("The way splits. One path has a cost: #{decision['text']}")
      resolve!(target["key"])
    when "key"
      update!(progress: progress.merge("keys" => keys_found | [ decision["lock"] ]))
      lock = view.fetch("paths", []).find { |p| p.dig("lock", "id") == decision["lock"] }&.dig("lock")
      campaign.narrate("Found #{decision['name']} in #{target['name']}.#{" It must open #{lock['name']}." if lock}", cue: "key")
      resolve!(target["key"])
    end
  end

  # What the GM might say as the party walks in on the boss, from the
  # place's past (Generators::Provenance): the room, what happened here, who
  # waits, and the boss's own line. The GM reads it out as it is, rewrites
  # it or clears it before the fight.
  def boss_prelude(target, who)
    past = view.fetch("past", {})
    fall = Generators::History::FALLS[past.dig("fall", "kind")]
    leader = campaign.world.monsters.where(slug: target.dig("decision", "monsters").to_h.keys).order(level: :desc).first
    lines = [ "#{target['name']}. #{fall ? fall['trace'] : 'The air is still, and something is waiting.'}" ]
    lost = Array(past["lost"]).last if fall
    if fall && past["was"]
      ago = past.dig("fall", "ago")
      lines << "#{ago ? Generators::History.ago(ago).upcase_first : 'Long ago'}, the #{[ past['family'], past['was'] ].compact.join(' ')} #{fall['did']}."
    end
    lines << (lost && lost == who ? "#{lost}, #{fall['dead']}, turns to face you." : "#{who || leader&.name || 'It'} turns to face you.")
    lines << "“#{leader.boss_line.strip}”" if leader&.boss_line.present?
    lines
  end
end
