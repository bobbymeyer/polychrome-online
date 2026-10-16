# frozen_string_literal: true

# A swing on a duel's meter (Duel#swing!), from whoever swings that side
# (Duel#swing_for?).
class Campaigns::Duels::SwingsController < Campaigns::BaseController
  def create
    duel = @campaign.duels.find(params[:duel_id])
    side = params.expect(:side)
    return forbid("That swing isn't yours.") unless duel.swing_for?(table_seat, side)

    duel.swing!(side, params.expect(:position))
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
