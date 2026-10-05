# frozen_string_literal: true

# GM tool at the table: EXP and ABP to someone outside battle (a quest
# reward, a montage), from GM tools' More.
class Campaigns::GrantsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action :require_table_gm

  def create
    character = @campaign.characters.find(params.expect(:character_id))
    grant = params.expect(grant: %i[exp abp])
    changes = character.gain!(exp: grant[:exp].to_i.clamp(0, 10**7), abp: grant[:abp].to_i.clamp(0, 10**5))
    redirect_back_or_to campaign_table_path(@campaign), notice: grant_notice(character, changes), status: :see_other
  end

  private

  def grant_notice(character, changes)
    parts = [ "#{character.name} gains #{changes['exp']} EXP and #{changes['abp']} ABP." ]
    parts << "Level #{changes['level'].last}!" if changes["level"]
    parts << "Learned #{changes['learned'].to_sentence}." if changes["learned"].any?
    parts.join(" ")
  end
end
