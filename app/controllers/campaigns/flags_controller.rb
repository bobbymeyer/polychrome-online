# frozen_string_literal: true

# The GM's campaign flags (§4).
class Campaigns::FlagsController < Campaigns::BaseController
  before_action :require_campaign_gm # Prep is the GM's account's, seated or not (TableSeat)
  before_action :set_flag, only: %i[update destroy]

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

  def destroy
    @flag.destroy!
    back notice: "Flag #{@flag.key} cleared."
  end

  private

  def set_flag
    @flag = @campaign.flags.find(params[:id])
  end

  def flag_params
    params.expect(flag: %i[key value note])
  end

  def back(notice: nil, alert: nil)
    redirect_to campaign_prep_path(@campaign, anchor: "flags"), notice: notice, alert: alert, status: :see_other
  end
end
