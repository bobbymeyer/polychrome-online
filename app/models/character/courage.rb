# frozen_string_literal: true

# A coward has no place in Oda (docs/ODA.md). Whoever refuses a duel is one,
# for everyone to see, until they fight another and win it. Meanwhile:
#   - no mask will have them (Battle::Masks), and they find no desperation
#     move (Battle::Resolver#desperate);
#   - nobody hires a coward: no payoff at a rest (Campaign::Payoffs);
#   - every town charges the party more while one travels with it
#     (Location::Town#price_here).
module Character::Courage
  extend ActiveSupport::Concern

  # What a coward costs the party, in percent on every price.
  COWARD_PRICE = 25

  def refuse_duel!(challenger)
    update!(coward: true)
    campaign.narrate("#{name} refuses #{challenger}'s challenge. A coward has no place in this world.")
  end

  # A duel won: the shame is gone, and the table hears it.
  def redeem!
    return unless coward?

    update!(coward: false)
    campaign.narrate("#{name} stood and fought, and won. Nobody calls them a coward now.")
  end
end
