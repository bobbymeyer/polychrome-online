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

  # The master's room: where the boss waits, or an antagonist who lives here.
  def master_room
    view.fetch("rooms", []).find { |r| r.dig("decision", "kind") == "boss" }
  end

  # Somewhere an antagonist can be met (Campaign::Overnight moves them only here).
  def lair? = !master_room.nil?

  # Its master has been dealt with (in any master's room the GM added, too).
  def cleared?
    view.fetch("rooms", []).any? { |r| r.dig("decision", "kind") == "boss" && resolved?(r["key"]) }
  end

  # An antagonist has moved in: the master's room waits for the party again.
  def await_villain!
    room = master_room or return
    reopen_room!(room["key"])
  end

  # What waits in a room is there again the next time the party walks in.
  def reopen_room!(key)
    return unless key

    update!(progress: progress.merge("resolved" => progress.fetch("resolved", []) - [ key ]))
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

    toll = toll_of(path)
    toll&.outcomes&.each { |outcome| outcome.can_happen!(campaign) }
    raise Refusal, "The party has #{campaign.money(campaign.gil)}; that way costs #{campaign.money(toll.price)}" if toll && toll.price > campaign.gil

    transaction do
      walk_away_from_fight!(to: key)
      pay!(path, toll) if path&.dig("cost") && !paid?(path)
      if lock
        update!(progress: progress.merge("unlocked" => progress.fetch("unlocked", []) | [ lock["id"] ]))
        campaign.narrate("#{name}: #{lock['key_name']} opens #{lock['name']}. The way is clear.", cue: "door")
      end
      update!(progress: progress.merge("current" => key, "visited" => (visited | [ key ])))
      campaign.narrate("#{name}: the party enters #{target['name']}.", data: Campaign::MOVED)
      announce(target) unless resolved?(key)
      campaign.drop_stale_where_next!
    end
  end

  # Hand a room's treasure to the party (once): money, or the item, found
  # (Outcome), in the place's own words.
  def take_treasure!(key)
    target = room(key)
    raise Refusal, "No treasure there" unless target && target["decision"]["kind"] == "treasure" && !resolved?(key)

    decision = target["decision"]
    item = campaign.world.items.find_by(slug: decision["item"]) if decision["item"]
    line = "Found #{describe_treasure(decision)} in #{target['name']}.#{" #{who_can_use(item)}" if item&.equipment?}"
    found = decision["gil"] ? Outcome.of("money", decision["gil"].to_i) : Outcome.of("find", target: { "item" => decision["item"] })
    said = transaction do
      resolve!(key)
      campaign.narrate(found.apply!(campaign, by: "The party", line: line), cue: "treasure").body
    end
    campaign.table_changed # the table's "Take it" goes
    said
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
    found = decision["gil"] ? campaign.money(decision["gil"]) : campaign.world.items.find_by(slug: decision["item"])&.name || decision["item"]
    heirloom = decision["heirloom"]
    return found unless heirloom

    made = [ ("made by #{heirloom['maker']}" if heirloom["maker"]), ("for #{heirloom['made_for']}" if heirloom["made_for"]) ].compact.join(" ")
    "#{found}, with #{heirloom['name']}#{" (#{made})" if made.present?}"
  end

  # A costly way is paid the first time the party goes that way, either way
  # round; after that it's just a way.
  def paid?(path)
    progress.fetch("paid", []).include?(path["key"])
  end

  # What a costly way still takes (Toll), or nil: none, or paid.
  def toll_of(path)
    return unless path&.dig("cost") && !paid?(path)

    toll = Toll.of(path["cost"])
    toll unless toll.free?
  end

  def resolve!(key)
    update!(progress: progress.merge("resolved" => (progress.fetch("resolved", []) | [ key ])))
  end

  private

  # The way's toll: the table hears what it costs, the party pays, what it
  # takes happens (Outcome), and the time goes by.
  def pay!(path, toll)
    campaign.narrate("The cost of that way: #{Toll.of(path['cost']).words}")
    if toll
      campaign.decrement!(:gil, toll.price) if toll.price.positive?
      campaign.narrate("The party pays #{campaign.money(toll.price)}.") if toll.price.positive?
      toll.outcomes.each do |outcome|
        said = outcome.apply!(campaign, by: "The party")
        campaign.narrate(said) if said
      end
      campaign.pass_time!(toll.takes) if toll.takes.positive?
    end
    update!(progress: progress.merge("paid" => progress.fetch("paid", []) | [ path["key"] ]))
  end

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
    when "boss"
      (villain = resident_villain) ? meet_villain(target, villain) : call_encounter(target)
    when "encounter"
      call_encounter(target)
    when "treasure"
      campaign.narrate("There is treasure in #{target['name']}.")
    when "fork"
      path = view.fetch("paths", []).find { |p| p["key"] == decision["costly_path"] }
      worth = { "shortcut" => " It looks like the quicker way down.", "treasure" => " Something glints that way." }[path&.dig("gain")]
      campaign.narrate("The way splits. One path has a cost: #{Toll.of(decision['text']).words}#{worth}")
      resolve!(target["key"])
    when "key"
      update!(progress: progress.merge("keys" => keys_found | [ decision["lock"] ]))
      lock = view.fetch("paths", []).find { |p| p.dig("lock", "id") == decision["lock"] }&.dig("lock")
      campaign.narrate("Found #{decision['name']} in #{target['name']}.#{" It must open #{lock['name']}." if lock}", cue: "key")
      resolve!(target["key"])
    end
  end

  # A room's fight waits for the GM to call or wave off (like on the map).
  def call_encounter(target)
    decision = target["decision"]
    boss = decision["kind"] == "boss"
    label = boss ? "The master of #{name}" : "#{name}: #{target['name']}"
    # Who the place's past says waits here (Generators::Provenance) is who
    # the table fights: the strongest of them takes that name.
    who = decision["who"].to_s.split(",").first.presence
    leader = who && campaign.world.monsters.where(slug: decision["monsters"].keys).order(level: :desc).first
    campaign.waylay!(label, decision["monsters"], boss: boss, terrain: location_template.encounter_table&.terrain_type,
                                                  names: ({ leader.slug => who } if leader), location: id, room: target["key"],
                                                  prelude: (boss_prelude(target, who) if boss))
    campaign.narrate("#{boss ? 'Boss' : 'Encounter'}! #{"#{who}: " if leader}#{campaign.describe_encounter(decision['monsters'])}.")
    resolve!(target["key"])
  end

  # The one the story has been about lives here (the setting's cast, brought
  # in by Atlas, or the GM's own antagonist): the boss room is theirs. They
  # take the strongest monster's place at the head of what waits there, and
  # the entrance is theirs too.
  def meet_villain(target, villain)
    monsters = target.dig("decision", "monsters").to_h.dup
    leader = campaign.world.monsters.where(slug: monsters.keys).order(level: :desc).first
    if leader
      monsters[leader.slug] -= 1
      monsters.delete(leader.slug) unless monsters[leader.slug].positive?
    end
    campaign.waylay!("#{villain.name}, in #{name}", monsters, boss: true, terrain: location_template.encounter_table&.terrain_type,
                                                               antagonists: [ villain.id ], location: id, room: target["key"],
                                                               prelude: villain_prelude(target, villain))
    with = monsters.any? ? ", with #{campaign.describe_encounter(monsters)}" : ""
    campaign.narrate("Boss! #{villain.name}#{", #{villain.title}" if villain.title.present?}#{with}.")
    resolve!(target["key"])
  end

  # The antagonist who calls this place home and is still at large.
  def resident_villain
    campaign.npcs.at_large.where(location_id: id).order(:id).first
  end

  def villain_prelude(target, villain)
    past = view.fetch("past", {})
    fall = campaign.world.lore.dig("falls", past.dig("fall", "kind"))
    lines = [ "#{target['name']}. #{fall&.dig('trace') || 'The air is still, and something is waiting.'}" ]
    lines << "#{villain.name}#{", #{villain.title.downcase_first}," if villain.title.present?} turns to face you."
    said = villain.world_figure&.blurb.presence || villain.description.presence
    lines << said if said
    lines << "#{villain.name}: #{villain.monster.boss_line.strip}" if villain.monster&.boss_line.present? # in their own box (Scene.read_line)
    lines
  end

  # What the GM might say as the party walks in on the boss, from the
  # place's past (Generators::Provenance): the room, what happened here, who
  # waits, and the boss's own line. The GM reads it out as it is, rewrites
  # it or clears it before the fight.
  def boss_prelude(target, who)
    past = view.fetch("past", {})
    fall = campaign.world.lore.dig("falls", past.dig("fall", "kind"))
    leader = campaign.world.monsters.where(slug: target.dig("decision", "monsters").to_h.keys).order(level: :desc).first
    lines = [ "#{target['name']}. #{fall&.dig('trace') || 'The air is still, and something is waiting.'}" ]
    lost = Array(past["lost"]).last if fall
    if fall && past["was"]
      ago = past.dig("fall", "ago")
      lines << "#{ago ? Generators::History.ago(ago).upcase_first : 'Long ago'}, the #{[ past['family'], past['was'] ].compact.join(' ')} #{fall['did'] || 'fell'}."
    end
    lines << (lost && lost == who && fall["dead"] ? "#{lost}, #{fall['dead']}, turns to face you." : "#{who || leader&.name || 'It'} turns to face you.")
    lines << "“#{leader.boss_line.strip}”" if leader&.boss_line.present?
    lines
  end
end
