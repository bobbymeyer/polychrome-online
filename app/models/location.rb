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
  has_one :map_node, dependent: :nullify
  has_many :npcs, dependent: :nullify

  validates :seed, numericality: { only_integer: true }
  validate :template_from_this_world

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

  def generated
    @generated ||= if town?
      Generators::Town.generate(seed: seed, template: location_template.settings, tables: location_template.table_entries)
    else
      Generators::Dungeon.generate(seed: seed, template: location_template.settings,
                                   encounters: location_template.encounter_table&.entries || [],
                                   tables: location_template.table_entries)
    end
  end

  def view
    @view ||= Generators::Overrides.apply(generated, overrides)
  end

  def reload(*)
    @generated = @view = nil
    super
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
    if (npc = view.fetch("npcs", []).find { |n| n["key"] == key })
      campaign.npcs.create!(name: npc["name"], title: npc["title"], description: npc["hook"], location: self, location_key: key)
      touch
    else
      element = (view.fetch("services", []) + view.fetch("rooms", [])).find { |e| e["key"] == key }
      raise ArgumentError, "Nothing called #{key} here" unless element

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
    raise ArgumentError, "No room #{connect} to connect to" unless room(connect)

    world = campaign.world
    unknown = Array(decision["monsters"]&.keys) - world.monsters.pluck(:slug)
    raise ArgumentError, "Pick a monster from the Bestiary" if decision["kind"] == "encounter" && (unknown.any? || decision["monsters"].empty?)
    raise ArgumentError, "Pick an item from the Armory" if decision["kind"] == "treasure" && !world.items.exists?(slug: decision["item"])

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
    else raise ArgumentError, "Unknown change #{kind}"
    end
  end

  # Remove a hand-authored room, and any rooms added off it.
  def remove_room!(key)
    added = overrides.fetch("added_rooms", [])
    raise ArgumentError, "No added room #{key}" unless added.any? { |r| r["key"] == key }

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
    slots = view.fetch("npcs", []).map do |generated|
      { "npc" => real.find { |n| n.location_key == generated["key"] }, "generated" => generated }
    end
    slots + real.select { |n| n.location_key.nil? }.map { |npc| { "npc" => npc, "generated" => nil } }
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

  def enter!
    move_to!(view["entrance"], from: nil)
  end

  # Move the party to a room next to the one they're in, and play out its
  # decision at the table: an event is narrated; an encounter or the boss
  # waits for the GM to fight or wave off (like on the map); treasure waits
  # to be handed over; a fork shows its visible cost.
  def move_to!(key, from: progress["current"])
    target = room(key) or raise ArgumentError, "No such room"
    raise ArgumentError, "That room isn't next to this one" if from && !neighbours(from).include?(key)

    path = from && path_between(from, key)
    transaction do
      update!(progress: progress.merge("current" => key, "visited" => (visited | [ key ])))
      campaign.messages.create!(kind: "system", body: "#{name}: the party enters #{target['name']}.")
      campaign.messages.create!(kind: "system", body: "The cost of that way: #{path['cost']}") if path&.dig("cost")
      announce(target) unless resolved?(key)
    end
  end

  # Hand a room's treasure to the party (once).
  def take_treasure!(key)
    target = room(key)
    raise ArgumentError, "No treasure there" unless target && target["decision"]["kind"] == "treasure" && !resolved?(key)

    item = campaign.world.items.find_by(slug: target["decision"]["item"])
    transaction do
      campaign.add_item!(item) if item
      resolve!(key)
      campaign.messages.create!(kind: "system", body: "Found #{item&.name || target['decision']['item']} in #{target['name']}.")
    end
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
      campaign.update!(pending_encounter: { "table" => label, "monsters" => decision["monsters"] })
      campaign.messages.create!(kind: "system", body: "#{decision['kind'] == 'boss' ? 'Boss' : 'Encounter'}! #{campaign.describe_encounter(decision['monsters'])}.")
      resolve!(target["key"])
    when "treasure"
      campaign.messages.create!(kind: "system", body: "There is treasure in #{target['name']}.")
    when "fork"
      campaign.messages.create!(kind: "system", body: "The way splits. One path has a cost: #{decision['text']}")
      resolve!(target["key"])
    end
  end

  def template_from_this_world
    return unless location_template && campaign

    errors.add(:location_template, "must come from #{campaign.world.name}") unless location_template.world_id == campaign.world_id
  end
end
