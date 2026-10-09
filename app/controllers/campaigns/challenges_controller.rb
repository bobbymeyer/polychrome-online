# frozen_string_literal: true

# Duels at the table (Campaign::Duels). The GM puts up a challenge: someone
# they play calls a character out, and the character's player answers
# (Challenges::AnswersController); or a character's own challenge, taken,
# and the duel starts at once. The GM can withdraw a challenge nobody
# answered.
class Campaigns::ChallengesController < Campaigns::BaseController
  before_action :require_table_gm

  def create
    character = @campaign.characters.find(params.expect(:character_id))
    npc = @campaign.duellists.find(params[:npc_id]) if params[:npc_id].present?
    monster = @campaign.world.monsters.find_by!(slug: params[:monster]) if params[:monster].present? && !npc
    if params[:by] == "character"
      @campaign.call_out!(character: character, npc: npc, monster: monster)
    else
      @campaign.challenge!(character: character, npc: npc, monster: monster, line: params[:line])
    end
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end

  def destroy
    @campaign.withdraw_challenge!
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
