# frozen_string_literal: true

# The GM's campaign flags (§4).
class FlagsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action :require_gm
  before_action :set_flag, only: %i[update destroy bump]

  def create
    flag = @campaign.flags.new(flag_params)
    if flag.save
      back notice: "Flag #{flag.key} set."
    else
      back alert: flag.errors.full_messages.to_sentence
    end
  end

  def update
    @flag.update(flag_params) ? back(notice: "Flag #{@flag.key} updated.") : back(alert: @flag.errors.full_messages.to_sentence)
  end

  def bump
    @flag.bump!(params[:by].to_i.clamp(-100, 100))
    back
  rescue Refusal => e
    back alert: e.message
  end

  def destroy
    @flag.destroy!
    back notice: "Flag #{@flag.key} cleared."
  end

  private

  def require_gm
    head :forbidden unless table_gm?
  end

  def set_flag
    @flag = @campaign.flags.find(params[:id])
  end

  def flag_params
    params.expect(flag: %i[key value note public])
  end

  def back(notice: nil, alert: nil)
    redirect_to campaign_path(@campaign, anchor: "flags"), notice: notice, alert: alert, status: :see_other
  end
end
