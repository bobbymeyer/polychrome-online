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
    names = tables.fetch("names", []).map { |e| e["text"] }
    rolled.each_with_index.map do |npc, i|
      if pinned_here.exclude?(npc["key"]) && taken.include?(npc["name"])
        free = names.rotate((seed + i) % [ names.size, 1 ].max).find { |name| taken.exclude?(name) && rolled.none? { |n| n["name"] == name } }
        npc = npc.merge("name" => free || "#{npc['name']} the Younger")
      end
      taken << npc["name"]
      npc
    end
  end

  # How the town sees the party, -5 to 5: the sway of every deed whose
  # story has got here (Campaign::Deeds), struck deeds not included.
  def reputation
    @reputation ||= map_node ? campaign.rumours.about_deeds.at(map_node).sum(:sway).clamp(-5, 5) : 0
  end

  def reload(*)
    @reputation = nil
    super
  end

  class_methods do
    # The reputation of every town on a list of map nodes, in one query.
    def preload_reputations(nodes)
      nodes = nodes.select(&:location)
      return nodes if nodes.empty?

      sways = RumourPlace.where(map_node_id: nodes.map(&:id)).joins(:rumour)
                         .merge(Rumour.about_deeds.where(campaign_id: nodes.first.campaign_id))
                         .group(:map_node_id).sum("rumours.sway")
      nodes.each { |node| node.location.instance_variable_set(:@reputation, sways.fetch(node.id, 0).clamp(-5, 5)) }
    end
  end

  STANDINGS = { -5..-3 => "Unwelcome", -2..-1 => "Wary", 0..0 => "Strangers", 1..2 => "Welcome", 3..5 => "Heroes" }.freeze
  REPUTATION_PRICE = 5 # percent off for each point in the party's favour

  def standing = STANDINGS.find { |range, _| range.cover?(reputation) }.last

  # Nobody here will trade with them, or give them a bed.
  def shuns_party? = reputation <= -3

  # What anything costs here today, the shop's stock and the inn, temple
  # and guild alike: dearer after a caravan is lost on
  # the road, easing back day by day (Campaign::Overnight), and cheaper for
  # friends.
  def price_here(base) = (base * (100 + prices - (REPUTATION_PRICE * reputation)).clamp(10, 300) / 100.0).round

  def price_of(item) = price_here(item.price)

  # Shops pay half.
  def resale_price_of(item) = price_of(item) / 2

  # What the inn, temple and guild charge: gil per level of each character
  # served, with a floor (a rumour costs the same for anyone), at the
  # town's prices.
  SERVICE_PRICES = { "inn" => [ 5, 10 ], "temple" => [ 20, 50 ], "guild" => [ 0, 30 ] }.freeze

  def service_price(kind, character = nil)
    per_level, floor = SERVICE_PRICES.fetch(kind)
    price_here([ per_level * character&.level.to_i, floor ].max)
  end

  # The inn, temple and guild, as things to do here (Pastime) with a price
  # and an outcome (Outcome): rooms for the whole party at the inn, a
  # raising at the temple for whoever is KO'd, a rumour at the guild. None
  # where a mode has shut them, or if the town won't deal with the party.
  def services_for(party)
    return [] unless town? && !shuns_party?

    open_services.filter_map do |service|
      case service["kind"]
      when "inn"
        Pastime.new(name: "Rooms at #{service['name']}", takes: 0, price: party.sum { |c| service_price("inn", c) },
                    outcomes: [ Outcome.of("rest", 100) ], service: "inn")
      when "temple"
        fallen = party.reject(&:conscious?)
        next if fallen.empty?

        Pastime.new(name: "A raising at #{service['name']}", takes: 0, price: fallen.sum { |c| service_price("temple", c) },
                    outcomes: [ Outcome.of("raise") ], service: "temple")
      when "guild"
        Pastime.new(name: "Rumours at #{service['name']}", takes: 0, price: service_price("guild"), outcomes: [ Outcome.of("rumour") ], service: "guild")
      end
    end
  end

  # The inn, if there's one open here.
  def inn = (open_services.find { |s| s["kind"] == "inn" } if town?)

  def stock_items
    slugs = view.fetch("stock", [])
    items = campaign.world.items.where(slug: slugs).index_by(&:slug)
    slugs.filter_map { |slug| items[slug] }
  end

  # A townsfolk hook that names the map ({town}, {dungeon}, {place}): the
  # nearest of each by road from here, so the hook points somewhere real.
  PLACE_TOKENS = { "town" => { kind: "town" }, "dungeon" => { kind: "dungeon" }, "place" => {} }.freeze

  def fill_in(text)
    return text unless text.to_s.include?("{")

    here = map_node
    @roads ||= campaign.roads # once for all of a page's hooks
    text.gsub(/\{(#{PLACE_TOKENS.keys.join('|')})\}/) do
      among = campaign.map_nodes.where(PLACE_TOKENS.fetch(Regexp.last_match(1))).where.not(id: here&.id)
      campaign.nearest(here, among, roads: @roads)&.name || "somewhere far off"
    end
  end

  private

  def open_services = view.fetch("services", []).reject { |service| shut_by(service["kind"]) }
end
