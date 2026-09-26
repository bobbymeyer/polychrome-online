# frozen_string_literal: true

# The GM's map overview: where the party is, the pending encounter, and
# the paths out.
class MapPanelsController < ApplicationController
  include CampaignScoped
  include MapGm

  before_action :set_campaign, :require_gm

  def show
    render layout: false
  end
end
