# frozen_string_literal: true

# The challenged character answers (Campaign::Duels): their player, or the
# GM for a character nobody is playing. Accept, and the duel starts; refuse,
# and they are a coward until they win one.
class Campaigns::Challenges::AnswersController < Campaigns::BaseController
  def create
    character = @campaign.challenged_character or return redirect_back_or_to(campaign_table_path(@campaign), status: :see_other)
    seat = table_seat
    return forbid("Only #{character.name} can answer that.") unless seat.gm? || seat.character == character

    @campaign.answer_challenge!(accept: params.expect(:answer) == "accept")
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
