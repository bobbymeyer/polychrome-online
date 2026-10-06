# frozen_string_literal: true

# What a townsperson wishes for (Generators::Town#couplets), and the party
# meeting it. A wish for an item is a thing to do in their town while the
# party holds it, in the chest or a bag, ("Bring Oskar a Remedy": a vote like any other, Campaign::
# Ways); a wish for the nearest dungeon cleared is met when the town
# welcomes the party back for clearing it, and they're the one who says so
# (Campaign::Deeds#welcome_back!). Either is a deed, so the town thinks
# better of the party. Each is met once; the town's #progress keeps whose.
module Location::Wishes
  extend ActiveSupport::Concern

  def met?(key)
    progress.fetch("met", []).include?(key)
  end

  # Things to do here for the wishes the party can meet now.
  def wishes
    return [] unless town?

    held = campaign.party_holdings.transform_values(&:first)
    townsfolk.filter_map do |person|
      item = held[person["wants"]] or next
      next if met?(person["key"])

      Pastime.new(name: "Bring #{person['name']} #{Wording.a_or_an(item.name)}", takes: 0, service: "wish", wish: person["key"])
    end
  end

  # The party hands over what they wished for, from the chest or a bag.
  def meet_wish!(key, by: "The party")
    person = townsfolk.find { |p| p["key"] == key } or raise Refusal, "Nobody like that lives here"
    raise Refusal, "#{person['name']} already has what they wished for" if met?(key)

    item = campaign.world.items.find_by(slug: person["wants"]) or raise Refusal, "#{person['name']} isn't asking for anything the party carries"
    raise Refusal, "There's no #{item.name} in the chest or anyone's bag" unless campaign.party_quantity_of(item).positive?

    transaction do
      campaign.take_from_party!(item)
      met!(key)
      campaign.narrate("#{by} gives #{person['name']} #{Wording.a_or_an(item.name)}. “#{thanks(key)}”")
      campaign.record_deed!("#{campaign.party_names} did #{person['name']} of #{name} a good turn.", at: map_node, sway: 1, kind: "favour", seen: true)
    end
  end

  # Whoever here wished the dungeon a {dungeon} names cleared, if it's this one.
  def wished_cleared(place)
    townsfolk.find do |person|
      person["wish"].to_s.include?("{dungeon}") && !met?(person["key"]) && fill_in("{dungeon}") == place
    end
  end

  def met!(key) = remember_in_progress!("met", key)

  private

  def thanks(key) = THANKS[(seed + key[/\d+/].to_i) % THANKS.size]

  THANKS = [ "I won't forget this.", "You didn't have to. Thank you.", "I'd started to think nobody would.",
             "Tell anyone who asks: this town owes you.", "Now I can sleep." ].freeze
end
