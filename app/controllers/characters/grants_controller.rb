# frozen_string_literal: true

# GM tool: grant EXP and ABP outside battle (a quest reward, a montage).
class Characters::GrantsController < ApplicationController
  include CampaignScoped

  before_action :set_character
  before_action :require_campaign_gm

  def create
    grant = params.expect(grant: %i[exp abp])
    exp = grant[:exp].to_i.clamp(0, 10**7)
    abp = grant[:abp].to_i.clamp(0, 10**5)
    changes = @character.gain!(exp: exp, abp: abp)
    redirect_to character_path(@character), notice: grant_notice(changes), status: :see_other
  end

  private

  def grant_notice(changes)
    parts = [ "#{@character.name} gains #{changes['exp']} EXP and #{changes['abp']} ABP." ]
    parts << "Level #{changes['level'].last}!" if changes["level"]
    parts << "Learned #{changes['learned'].to_sentence}." if changes["learned"].any?
    parts.join(" ")
  end
end
