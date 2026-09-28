# frozen_string_literal: true

# A town or dungeon in a campaign (docs/HANDOFF.md §4, §7): a template, a
# seed, and GM overrides. What's in it is never stored; #view regenerates it
# from those every time (Generators::Town / ::Dungeon, then
# Generators::Overrides), so a reroll is just a new seed.
#
# Town NPCs the GM pins become real campaign NPCs (they can then be spoken
# as at the table). A dungeon is a nested pointcrawl: #progress records the
# party's room and what they've seen and dealt with.
class Location < ApplicationRecord
  belongs_to :campaign
  belongs_to :location_template
  has_many :mode_arts, dependent: :destroy
  has_one :map_node, dependent: :nullify
  has_many :npcs, dependent: :nullify

  validates :seed, numericality: { only_integer: true }
  validate :template_from_this_world
  validate :modes_are_modes

  before_validation(on: :create) { self.seed ||= Location.new_seed }

  # Rails 8 page refreshes: each viewer re-fetches their own page, so a
  # player's copy never contains what only the GM may see.
  after_update_commit :broadcast_refresh
  after_save { @generated = @view = nil }

  delegate :town?, :dungeon?, :kind, to: :location_template

  def self.new_seed
    Random.new_seed % 2**31
  end

  def name
    view["name"]
  end

  # --- generation --------------------------------------------------------------

  # Rolled, then given its past (Generators::Provenance): a dungeon's rooms,
  # boss and treasure follow from what it was.
  def generated
    @generated ||= begin
      rolled = if town?
        in_the_worlds_words(Generators::Town.generate(seed: seed, template: town_settings, tables: location_template.table_entries))
      else
        Generators::Dungeon.generate(seed: seed, template: location_template.settings,
                                     encounters: location_template.encounter_table&.entries || [],
                                     tables: location_template.table_entries)
      end
      Generators::Provenance.apply(rolled, past_for(rolled["name"]), seed: seed)
    end
  end

  def view
    @view ||= with_stock_stories(Generators::Overrides.apply(generated, overrides))
  end

  # Its past: the atlas place's, written by the world's history (Chronicle)
  # or the GM; else a small one of its own, rolled from its seed.
  def past_for(name)
    written = map_node&.world_place&.past
    return written.except("edited") if Past.new(written).present?

    world = campaign.world
    Generators::Provenance.past_for(seed: seed, name: name, kind: kind,
                                    given_names: location_template.table_entries.fetch("names", []).filter_map { |e| e["text"] },
                                    family_names: world.generator_tables.of_kind("families").flat_map { |t| t.entries.filter_map { |e| e["text"] } })
  end

  def past = Past.new(generated["past"])

  # Who made the shop's made things (not its potions), and who had them.
  def with_stock_stories(view)
    return view unless view["kind"] == "town" && view["stock"].present?

    made = campaign.world.items.where(slug: view["stock"]).where.not(category: "consumable").pluck(:slug)
    view.merge("stock_stories" => Generators::Provenance.stock(made.sort, view["past"], seed: seed))
  end

  # The template's settings, less the services this world doesn't have.
  def town_settings
    settings = location_template.settings
    off = campaign.world.services_off
    return settings if off.empty?

    settings.merge("services" => settings.fetch("services", {}).merge(off.index_with(0)))
  end

  # A keeper is named for the world's word for their service.
  def in_the_worlds_words(town)
    world = campaign.world
    town.merge("npcs" => town["npcs"].map do |npc|
      kind = npc["service"]
      kind && world.terms.dig("services", kind) ? npc.merge("title" => "#{world.word("service.#{kind}")} keeper") : npc
    end)
  end

  def reload(*)
    @generated = @view = nil
    super
  end

  # --- modes: the place's other states --------------------------------------
  #
  # A mode is prepared by the GM and set off at the table: the city burns,
  # the mine floods, the festival starts. While it lasts, some services are
  # shut, the music changes, there can be trouble on arrival (an encounter
  # table), and players read a line about it. The world doesn't change.
  #
  #   { "key" => "burning", "name" => "Burning", "line" => "Smoke over the rooftops: Tule is burning.",
  #     "description" => "Half the market is ash.", "closed" => ["shop"], "music" => "battle",
  #     "encounters" => "town_riot" }

  def current_mode
    modes.find { |t| t["key"] == mode } if mode
  end

  def service_closed?(kind)
    Array(current_mode&.dig("closed")).include?(kind.to_s)
  end

  def encounter_table_for_mode
    slug = current_mode&.dig("encounters")
    slug && campaign.world.encounter_tables.find_by(slug: slug)
  end

  def add_mode!(attrs)
    name = attrs["name"].to_s.strip
    raise Refusal, "A mode needs a name" if name.empty?

    key = name.parameterize(separator: "_")
    raise Refusal, "#{view['name']} already has a mode called #{name}" if modes.any? { |t| t["key"] == key }

    entry = { "key" => key, "name" => name, "line" => attrs["line"].to_s.strip.presence, "description" => attrs["description"].to_s.strip.presence,
             "closed" => Array(attrs["closed"]).compact_blank, "music" => attrs["music"].presence,
             "encounters" => attrs["encounters"].presence, "art" => attrs["art"].to_s.strip.presence }.compact
    update!(modes: modes + [ entry ])
  end

  def remove_mode!(key)
    transaction do
      mode_arts.where(mode_key: key).destroy_all
      update!(modes: modes.reject { |t| t["key"] == key }, mode: (mode unless mode == key))
    end
  end

  # How a mode changes the place's picture (§8): words after the rest of
  # the prompt ("on fire, thick smoke, ash falling").
  def set_mode_art!(key, words)
    raise Refusal, "#{name} has no mode called #{key}" unless modes.any? { |t| t["key"] == key }

    update!(modes: modes.map { |t| t["key"] == key ? t.merge("art" => words.to_s.strip.presence).compact : t })
  end

  # The place's picture as it is now: the mode's own, if it has one, else
  # the Gazetteer entry's. nil when neither has been made.
  def picture
    in_mode = current_mode && mode_arts.find_by(mode_key: mode)
    return in_mode.image if in_mode&.image&.attached?

    location_template.image if location_template.image.attached?
  end

  # Sets the mode off, and tells the table.
  def switch_mode!(key)
    chosen = modes.find { |t| t["key"] == key } or raise Refusal, "#{view['name']} has no mode called #{key}"
    transaction do
      update!(mode: key)
      campaign.messages.create!(kind: "system", body: chosen["line"] || "#{view['name']}: #{chosen['name']}.")
    end
    campaign.broadcast_map
    campaign.broadcast_music
  end

  # Back to how it was.
  def clear_mode!(line = nil)
    was = current_mode or raise Refusal, "#{view['name']} is as it always was"
    transaction do
      update!(mode: nil)
      campaign.messages.create!(kind: "system", body: line.to_s.strip.presence || "#{view['name']} is itself again: #{was['name'].downcase} no more.")
    end
    campaign.broadcast_map
    campaign.broadcast_music
  end

  # --- GM controls (§7): reroll, pin, add, place boss, override stock ----------

  # A new seed. Pins, stock, boss and added rooms stay; a dungeon's
  # exploration starts over, since its rooms have moved.
  def reroll!
    update!(seed: Location.new_seed, progress: {})
  end

  def rename!(name)
    update!(overrides: overrides.merge("name" => name.to_s.strip.presence).compact)
  end

  def pinned?(key)
    overrides.fetch("pins", {}).key?(key) || npcs.exists?(location_key: key)
  end

  # Pin a service or room as it is now, so rerolls keep it. For a town NPC,
  # pinning makes them a real NPC of the campaign.
  def pin!(key)
    if (npc = townsfolk.find { |n| n["key"] == key })
      campaign.npcs.create!(name: npc["name"], title: npc["title"], description: npc["hook"], location: self, location_key: key)
      touch
    else
      element = (view.fetch("services", []) + view.fetch("rooms", [])).find { |e| e["key"] == key }
      raise Refusal, "Nothing called #{key} here" unless element

      update!(overrides: overrides.merge("pins" => overrides.fetch("pins", {}).merge(key => element)))
    end
  end

  def unpin!(key)
    npcs.where(location_key: key).destroy_all
    update!(overrides: overrides.merge("pins" => overrides.fetch("pins", {}).except(key)))
  end

  def set_stock!(item_slugs)
    stock = item_slugs&.compact_blank
    update!(overrides: stock.nil? ? overrides.except("stock") : overrides.merge("stock" => stock))
  end

  def place_boss!(monsters)
    monsters = monsters.to_h.reject { |slug, count| slug.blank? || count.to_i < 1 }.transform_values(&:to_i)
    update!(overrides: monsters.empty? ? overrides.except("boss") : overrides.merge("boss" => monsters))
  end

  def add_room!(name:, connect:, decision:)
    raise Refusal, "No room #{connect} to connect to" unless room(connect)

    world = campaign.world
    unknown = Array(decision["monsters"]&.keys) - world.monsters.pluck(:slug)
    raise Refusal, "Pick a monster from the Bestiary" if decision["kind"] == "encounter" && (unknown.any? || decision["monsters"].empty?)
    if decision["kind"] == "treasure" && !decision["gil"].to_i.positive? && !world.items.exists?(slug: decision["item"])
      raise Refusal, "Pick an item from the Armory, or an amount of #{world.word('currency')}"
    end

    added = overrides.fetch("added_rooms", [])
    key = "added-#{added.size + 1}"
    update!(overrides: overrides.merge("added_rooms" => added + [ { "key" => key, "name" => name, "decision" => decision, "connect" => connect } ]))
    key
  end

  # --- diffs (§7: GM diffs are overrides on top of the seed) --------------------

  # Every way the GM has changed this location from what was rolled, as
  # [{ "kind", "key", "summary" }], each revertible with #revert!.
  def changes
    list = []
    if overrides["name"]
      list << change("name", nil, "Renamed to #{overrides['name']} (rolled as #{generated['name']})")
    end
    overrides.fetch("pins", {}).each do |key, element|
      list << change("pin", key, "Pinned #{element['name']}")
    end
    npcs.order(:id).each do |npc|
      list << change("npc", npc.id.to_s,
                     npc.location_key ? "Pinned #{npc.name} (now a real NPC)" : "Wrote in #{npc.name}#{", #{npc.title}" if npc.title.present?}")
    end
    if overrides.key?("stock")
      names = campaign.world.items.where(slug: overrides["stock"]).pluck(:name)
      list << change("stock", nil, "Shop stock set to #{names.to_sentence.presence || 'nothing'}")
    end
    if overrides["boss"]
      list << change("boss", nil, "Boss placed: #{campaign.describe_encounter(overrides['boss'])}")
    end
    overrides.fetch("added_rooms", []).each do |room|
      list << change("room", room["key"], "Added room #{room['name']}")
    end
    list
  end

  def revert!(kind, key = nil)
    case kind
    when "name" then rename!(nil)
    when "pin" then unpin!(key)
    when "npc"
      npc = npcs.find(key)
      npc.location_key ? unpin!(npc.location_key) : npc.destroy!
      touch
    when "stock" then set_stock!(nil)
    when "boss" then place_boss!({})
    when "room" then remove_room!(key)
    else raise Refusal, "Unknown change #{kind}"
    end
  end

  # Remove a hand-authored room, and any rooms added off it.
  def remove_room!(key)
    added = overrides.fetch("added_rooms", [])
    raise Refusal, "No added room #{key}" unless added.any? { |r| r["key"] == key }

    doomed = [ key ]
    loop do
      more = added.select { |r| doomed.include?(r["connect"]) }.map { |r| r["key"] } - doomed
      break if more.empty?

      doomed.concat(more)
    end

    remaining = added.reject { |r| doomed.include?(r["key"]) }
    progress = self.progress.merge("visited" => visited - doomed)
    progress["current"] = view["entrance"] if doomed.include?(progress["current"])
    update!(overrides: overrides.merge("added_rooms" => remaining), progress: progress)
  end

  # --- town ---------------------------------------------------------------------

  # The roster: each generated slot shows its real NPC once pinned, then the
  # NPCs the GM wrote in. Returns [{ "npc" => Npc or nil, "generated" => hash or nil }].
  def roster
    real = npcs.order(:id).to_a
    slots = townsfolk.map do |generated|
      { "npc" => real.find { |n| n.location_key == generated["key"] }, "generated" => generated }
    end
    slots + real.select { |n| n.location_key.nil? }.map { |npc| { "npc" => npc, "generated" => nil } }
  end

  # The generated townsfolk as the table meets them. Someone the campaign's
  # cast already has a name for (a pinned or written-in NPC, here or
  # anywhere) isn't rolled twice: an unpinned townsperson who'd share their
  # name takes the next free name from the names table instead. Only the
  # clashing one changes, so the rest of the town stays as rolled.
  def townsfolk
    rolled = view.fetch("npcs", [])
    cast = campaign.npcs.to_a
    pinned_here = cast.select { |npc| npc.location_id == id && npc.location_key }.map(&:location_key)
    taken = cast.map(&:name) + rolled.select { |n| pinned_here.include?(n["key"]) }.map { |n| n["name"] }
    names = location_template.table_entries.fetch("names", []).map { |e| e["text"] }
    rolled.each_with_index.map do |npc, i|
      if pinned_here.exclude?(npc["key"]) && taken.include?(npc["name"])
        free = names.rotate((seed + i) % [ names.size, 1 ].max).find { |name| taken.exclude?(name) && rolled.none? { |n| n["name"] == name } }
        npc = npc.merge("name" => free || "#{npc['name']} the Younger")
      end
      taken << npc["name"]
      npc
    end
  end

  def stock_items
    slugs = view.fetch("stock", [])
    items = campaign.world.items.where(slug: slugs).index_by(&:slug)
    slugs.filter_map { |slug| items[slug] }
  end

  # --- dungeon ------------------------------------------------------------------

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
      if lock
        update!(progress: progress.merge("unlocked" => progress.fetch("unlocked", []) | [ lock["id"] ]))
        campaign.messages.create!(kind: "system", cue: "door", body: "#{name}: #{lock['key_name']} opens #{lock['name']}. The way is clear.")
      end
      update!(progress: progress.merge("current" => key, "visited" => (visited | [ key ])))
      campaign.messages.create!(kind: "system", body: "#{name}: the party enters #{target['name']}.")
      campaign.messages.create!(kind: "system", body: "The cost of that way: #{path['cost']}") if path&.dig("cost")
      announce(target) unless resolved?(key)
    end
  end

  # Hand a room's treasure to the party (once).
  def take_treasure!(key)
    target = room(key)
    raise Refusal, "No treasure there" unless target && target["decision"]["kind"] == "treasure" && !resolved?(key)

    decision = target["decision"]
    item = campaign.world.items.find_by(slug: decision["item"]) if decision["item"]
    transaction do
      campaign.add_item!(item) if item
      campaign.increment!(:gil, decision["gil"].to_i) if decision["gil"]
      resolve!(key)
      campaign.messages.create!(kind: "system", cue: "treasure", body: "Found #{describe_treasure(decision)} in #{target['name']}.")
    end
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

  def change(kind, key, summary)
    { "kind" => kind, "key" => key, "summary" => summary }
  end

  def announce(target)
    decision = target["decision"]
    case decision["kind"]
    when "event"
      campaign.messages.create!(body: decision["text"])
      resolve!(target["key"])
    when "encounter", "boss"
      label = decision["kind"] == "boss" ? "The master of #{name}" : "#{name}: #{target['name']}"
      campaign.update!(pending_encounter: { "table" => label, "monsters" => decision["monsters"], "boss" => decision["kind"] == "boss",
                                            "terrain" => location_template.encounter_table&.terrain_type }.compact)
      campaign.messages.create!(kind: "system", body: "#{decision['kind'] == 'boss' ? 'Boss' : 'Encounter'}! #{campaign.describe_encounter(decision['monsters'])}.")
      resolve!(target["key"])
    when "treasure"
      campaign.messages.create!(kind: "system", body: "There is treasure in #{target['name']}.")
    when "fork"
      campaign.messages.create!(kind: "system", body: "The way splits. One path has a cost: #{decision['text']}")
      resolve!(target["key"])
    when "key"
      update!(progress: progress.merge("keys" => keys_found | [ decision["lock"] ]))
      lock = view.fetch("paths", []).find { |p| p.dig("lock", "id") == decision["lock"] }&.dig("lock")
      campaign.messages.create!(kind: "system", cue: "key", body: "Found #{decision['name']} in #{target['name']}.#{" It must open #{lock['name']}." if lock}")
      resolve!(target["key"])
    end
  end

  def modes_are_modes
    world = campaign&.world or return
    Array(modes).each do |t|
      errors.add(:modes, "#{t['name']}: music must be one of #{Campaign::MUSIC_CHOICES.join(', ')}") if t["music"] && !Campaign::MUSIC_CHOICES.include?(t["music"])
      errors.add(:modes, "#{t['name']}: #{t['encounters']} isn't an encounter table") if t["encounters"] && !world.encounter_tables.exists?(slug: t["encounters"])
    end
    errors.add(:mode, "isn't one of this place's modes") if mode && Array(modes).none? { |t| t["key"] == mode }
  end

  def template_from_this_world
    return unless location_template && campaign

    errors.add(:location_template, "must come from #{campaign.world.name}") unless location_template.world_id == campaign.world_id
  end
end
