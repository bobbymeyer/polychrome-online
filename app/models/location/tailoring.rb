# frozen_string_literal: true

# The GM's changes on top of what was rolled (§7: reroll, pin, add
# hand-authored NPCs and rooms, place the boss, override stock). Each is an
# override, listed by #changes and undone by #revert!.
module Location::Tailoring
  extend ActiveSupport::Concern

  # A new seed. Pins, stock, boss and added rooms stay; a dungeon's
  # exploration starts over, since its rooms have moved.
  def reroll!
    update!(seed: Location.new_seed, progress: {}, overrides: overrides.except("tables", "families"))
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
      campaign.npcs.create!(name: npc["name"], title: npc["title"], description: fill_in(npc["hook"]), location: self, location_key: key)
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
    npcs.sort_by(&:id).each do |npc|
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
    if overrides.key?("tables")
      list << change("tables", nil, "Kept as the party found it: its people keep their names when the world's tables change")
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
    when "tables" then update!(overrides: overrides.except("tables", "families")) # rolled from the world's tables as they are now
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

  private

  def change(kind, key, summary)
    { "kind" => kind, "key" => key, "summary" => summary }
  end
end
