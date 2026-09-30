# frozen_string_literal: true

# The GM grants jobs at the table (Campaign#grant_jobs!): a story reward.
class Campaigns::JobGrantsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action :require_table_gm

  def create
    jobs = @campaign.world.jobs.where(slug: Array(params[:jobs]).compact_blank).to_a
    @campaign.grant_jobs!(jobs, params[:line])
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
