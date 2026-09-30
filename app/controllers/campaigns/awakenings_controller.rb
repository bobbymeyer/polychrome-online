# frozen_string_literal: true

# The GM has a character awaken to a job at the table (Campaign#awaken!).
class Campaigns::AwakeningsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action :require_table_gm

  def create
    character = @campaign.characters.find(params.expect(:character_id))
    job = @campaign.world.jobs.find_by!(slug: params.expect(:job))
    @campaign.awaken!(character, job, params[:line])
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  rescue Refusal => e
    redirect_back_or_to campaign_table_path(@campaign), alert: e.message, status: :see_other
  end
end
