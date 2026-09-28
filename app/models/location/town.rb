# frozen_string_literal: true

# A town's people and shop: the rolled townsfolk, the ones the GM pinned or
# wrote in, and what's on the shelves.
module Location::Town
  extend ActiveSupport::Concern

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
end
