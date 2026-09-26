# frozen_string_literal: true

module ShopsHelper
  # The GM shops anywhere; a player with a character in the campaign shops
  # in the town where the party is.
  def may_shop?(location)
    campaign = location.campaign
    return true if can_gm?(campaign)
    return false unless location.town? && campaign.current_node&.location_id == location.id

    campaign.characters.exists?(user: current_user)
  end
end
