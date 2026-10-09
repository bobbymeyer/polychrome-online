# frozen_string_literal: true

# A swing on a duel's meter (Duel#swing!): the challenged character's, from
# their player (or the GM, for a character nobody plays), and the
# opponent's, from the GM, who plays them.
class Campaigns::Duels::SwingsController < Campaigns::BaseController
  def create
    duel = @campaign.duels.find(params[:duel_id])
    side = params.expect(:side)
    seat = table_seat
    allowed = side == "gm" ? seat.gm? : (seat.character == duel.character || (seat.gm? && duel.character.user_id.nil?))
    return forbid("That swing isn't yours.") unless allowed

    duel.swing!(side, params.expect(:position))
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
