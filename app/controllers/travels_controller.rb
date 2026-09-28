# frozen_string_literal: true

class TravelsController < ApplicationController
  include CampaignScoped
  include MapGm

  before_action :set_campaign, :require_gm

  def create
    edge = @campaign.map_edges.find(params.expect(:edge_id))
    rolled = @campaign.travel!(edge)
    panel notice: rolled ? "Encounter! #{@campaign.describe_encounter(rolled)}." : "The party arrives safely."
  rescue Refusal => e
    panel alert: e.message
  end
end
