# frozen_string_literal: true

# The GM's changes on top of what was rolled (§7: reroll, pin, add
# hand-authored NPCs and rooms, place the boss, override stock). Each is an
# override, listed by #changes and undone by #revert!.
module Location::Tailoring
  extend ActiveSupport::Concern

  # A new seed. Pins, stock, boss and added rooms stay; a dungeon's
  # exploration starts over, since its rooms have moved.
  #
  # The shape goes with the roll. Moved rooms and joined or cut ways are
  # placed against one layout, and a reroll is a different one -- a
  # different room count, even (five_rooms rolls 4 to 6). Keeping them
  # would hang coordinates and doors off rooms that this roll didn't make.
  SHAPE = %w[moved_rooms added_paths removed_paths].freeze

  def reroll!
    update!(seed: Location.new_seed, progress: {}, overrides: overrides.except("tables", "families", *SHAPE))
  end

  # Take the world's tables again (Location::Generation#remember!): the
  # seed stays, so an atlas place keeps its layout; the names and rooms
  # are rolled from the tables as they are now.
  def forget_tables!
    raise Refusal, "#{view['name']} is rolled from the world's tables as they are" unless overrides.key?("tables")

    update!(overrides: overrides.except("tables", "families"))
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

  # Who waits in the boss room ({} for as rolled). Placing one sets the room
  # waiting again, even if the party has been through it.
  def place_boss!(monsters)
    raise Refusal, "#{name} has no boss room." unless view["boss"]

    monsters = monsters.to_h.reject { |slug, count| slug.blank? || count.to_i < 1 }.transform_values { |count| count.to_i.clamp(1, 8) }
    unknown = monsters.keys - campaign.world.monsters.where(slug: monsters.keys).pluck(:slug)
    raise Refusal, "#{unknown.to_sentence} #{unknown.one? ? "isn't" : "aren't"} in the Bestiary." if unknown.any?

    transaction do
      update!(overrides: monsters.empty? ? overrides.except("boss") : overrides.merge("boss" => monsters))
      reopen_room!(view["boss"]) unless campaign.pending_encounter&.dig("room") == view["boss"]
    end
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

  # How elaborate this dungeon is (Generators::Elaboration): 0 is the roll
  # as it came, 5 adds ten rooms of alcoves, side chains and passages
  # running parallel to the core. The core is untouched at every level --
  # same rooms, same order -- so this is safe to turn once the story is
  # pinned on.
  def elaboration
    overrides.fetch("elaboration", 0).to_i
  end

  def elaborate!(level)
    raise Refusal, "#{name} is a town." unless dungeon?

    level = level.to_i.clamp(0, Generators::Elaboration::MAX_LEVEL)
    before = view.fetch("rooms", []).map { |r| r["key"] }
    self.overrides = level.zero? ? overrides.except("elaboration") : overrides.merge("elaboration" => level)
    @generated = @view = nil # the rooms at the new level
    # Turned down, the rooms it took away go as a removed room does: off the party, the plan and the change list.
    dialled, progress = without_rooms(before - view.fetch("rooms", []).map { |r| r["key"] }, overrides)
    update!(overrides: dialled, progress: progress)
  end

  # Drag a room off where it rolled (Generators::Overrides "moved_rooms").
  # The floorplan's own coordinates, clamped to the sheet.
  def move_room!(key, x:, y:)
    raise Refusal, "No room #{key} here" unless room(key)

    at = [ x.to_i.clamp(0, Generators::Dungeon::WIDTH), y.to_i.clamp(0, Generators::Dungeon::HEIGHT) ]
    set_shape!("moved_rooms", overrides.fetch("moved_rooms", {}).merge(key => at))
  end

  # Join two rooms, so the party can walk between them. A plain way: no
  # lock, no toll -- those are the roll's to give.
  def connect_rooms!(from, to)
    here, there = room(from), room(to)
    raise Refusal, "No room #{here ? to : from} here" unless here && there
    raise Refusal, "#{here['name']} can't join itself" if from == to
    raise Refusal, "#{here['name']} and #{there['name']} are already joined" if path_between(from, to)

    set_shape!("added_paths", overrides.fetch("added_paths", []) + [ [ from, to ] ])
  end

  # Cut a way. Any way, the roll's included -- but not one that would
  # strand a room: a dungeon nobody can walk through isn't playable, and
  # the party has to be able to reach every room from the entrance.
  def cut_path!(key)
    path = view.fetch("paths", []).find { |p| p["key"] == key }
    raise Refusal, "No way #{key} here" unless path

    left = view.fetch("paths", []).reject { |p| p["key"] == key }
    stranded = rooms_off_the_entrance(left)
    if stranded.any?
      raise Refusal, "Cutting that way strands #{stranded.map { |r| r['name'] }.to_sentence}. Join #{stranded.one? ? 'it' : 'them'} elsewhere first."
    end

    # A way the GM drew comes out of added_paths rather than going into
    # removed_paths, so drawing then cutting leaves nothing behind.
    if path["added"]
      pair = [ path["from"], path["to"] ].sort
      set_shape!("added_paths", overrides.fetch("added_paths", []).reject { |p| p.sort == pair })
    else
      set_shape!("removed_paths", overrides.fetch("removed_paths", []) + [ key ])
    end
  end

  # A shape override, emptied back out of `overrides` rather than left as an
  # empty hash or list: elsewhere the code asks whether a key is there at all.
  def set_shape!(key, value)
    update!(overrides: value.presence ? overrides.merge(key => value) : overrides.except(key))
  end

  # Which rooms these ways leave unreachable from the entrance.
  def rooms_off_the_entrance(paths)
    rooms = view.fetch("rooms", [])
    reached = [ view["entrance"] ].compact
    loop do
      more = paths.filter_map do |path|
        (path["to"] if reached.include?(path["from"])) || (path["from"] if reached.include?(path["to"]))
      end.uniq - reached
      break if more.empty?

      reached.concat(more)
    end
    rooms.reject { |room| reached.include?(room["key"]) }
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
    if elaboration.positive?
      added = view.fetch("rooms", []).count { |room| room["elaborated"] }
      list << change("elaboration", nil, "Elaborated to #{elaboration} of #{Generators::Elaboration::MAX_LEVEL} (#{added} #{'room'.pluralize(added)} added)")
    end
    overrides.fetch("moved_rooms", {}).each_key do |key|
      list << change("moved", key, "Moved #{room(key)&.fetch('name') || key}")
    end
    overrides.fetch("added_paths", []).each do |from, to|
      list << change("path", Generators::Overrides.added_path_key(from, to), "Joined #{room_name(from)} to #{room_name(to)}")
    end
    overrides.fetch("removed_paths", []).each do |key|
      list << change("cut", key, "Cut the way #{rolled_path_name(key)}")
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
    when "elaboration" then elaborate!(0)
    when "moved" then set_shape!("moved_rooms", overrides.fetch("moved_rooms", {}).except(key))
    when "path" then cut_path!(key)
    when "cut" then set_shape!("removed_paths", overrides.fetch("removed_paths", []) - [ key ])
    when "tables" then update!(overrides: overrides.except("tables", "families")) # rolled from the world's tables as they are now
    else raise Refusal, "Unknown change #{kind}"
    end
  end

  # A room's name for the change list: from the view while it's there,
  # else the roll's, else the bare key.
  def room_name(key)
    room(key)&.fetch("name") || generated.fetch("rooms", []).find { |r| r["key"] == key }&.fetch("name") || key
  end

  # A cut way named by its ends. It isn't in the view any more -- that's
  # what cutting it did -- so the roll is where to look.
  def rolled_path_name(key)
    path = generated.fetch("paths", []).find { |p| p["key"] == key }
    return key unless path

    "#{room_name(path['from'])} – #{room_name(path['to'])}"
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
    kept, progress = without_rooms(doomed, overrides.merge("added_rooms" => remaining))
    update!(overrides: kept, progress: progress)
  end

  private

  # The overrides and progress once these rooms are gone: the party isn't
  # in them or remembered there, and their ways and places go with them,
  # so the change list stops naming them.
  def without_rooms(doomed, overrides)
    progress = self.progress.merge("visited" => visited - doomed)
    progress["current"] = view["entrance"] if doomed.include?(progress["current"])
    shape = { "added_paths" => overrides.fetch("added_paths", []).reject { |pair| pair.any? { |end_| doomed.include?(end_) } },
              "moved_rooms" => overrides.fetch("moved_rooms", {}).except(*doomed) }
    kept, emptied = shape.partition { |_, value| value.present? }
    [ overrides.merge(kept.to_h).except(*emptied.to_h.keys), progress ]
  end

  def change(kind, key, summary)
    { "kind" => kind, "key" => key, "summary" => summary }
  end
end
