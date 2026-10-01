# frozen_string_literal: true

# The GM's secrets and clues (Secret): written in prep, revealed at the table.
class Campaigns::SecretsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action :require_table_gm
  before_action :set_secret, only: %i[update destroy]

  def create
    secret = @campaign.secrets.new(secret_params)
    secret.save ? back(notice: "Secret kept.") : back(alert: secret.errors.full_messages.to_sentence)
  end

  # Its key and clues, rewritten.
  def update
    @secret.update(params.expect(secret: %i[key steps])) ? back(notice: "Secret saved.") : back(alert: @secret.errors.full_messages.to_sentence)
  end

  def destroy
    @secret.destroy!
    back notice: "Secret struck out."
  end

  private


  def set_secret
    @secret = @campaign.secrets.find(params[:id])
  end

  def secret_params
    attrs = params.expect(secret: %i[body location_id npc_id steps key])
    attrs.merge(location: attrs[:location_id].presence && @campaign.locations.find_by(id: attrs[:location_id]),
                npc: attrs[:npc_id].presence && @campaign.npcs.find_by(id: attrs[:npc_id])).except(:location_id, :npc_id)
  end

  def back(notice: nil, alert: nil)
    redirect_back_or_to campaign_prep_path(@campaign, anchor: "secrets"), notice: notice, alert: alert, status: :see_other
  end
end
