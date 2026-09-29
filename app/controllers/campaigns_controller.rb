# frozen_string_literal: true

class CampaignsController < ApplicationController
  include TableSeat

  before_action :set_campaign, only: %i[show edit update]
  before_action :require_campaign_gm, only: %i[edit update]

  def new
    @world = World.find_by!(slug: params[:world_slug])
    @campaign = @world.campaigns.new
  end

  def create
    @world = World.find_by!(slug: params[:world_slug])
    @campaign = @world.campaigns.new(params.expect(campaign: %i[name]).merge(gm: current_user, open_jobs: posted_open_jobs))
    if @campaign.save
      @campaign.set_out!(from_the_setting: params[:blank_map] != "1")
      redirect_to @campaign, notice: "#{@campaign.name} begins."
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    @characters = @campaign.characters.includes(:job, :user, :character_jobs, equipment_slots: :item).order(:created_at)
    @battles = @campaign.battles.order(created_at: :desc).limit(10)
  end

  def edit; end

  def update
    # Only an admin hands a campaign to another GM.
    if @campaign.update(params.expect(campaign: admin? ? %i[name gil gm_id] : %i[name gil]).merge(open_jobs: posted_open_jobs))
      redirect_to @campaign, notice: "#{@campaign.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  # The form's job boxes: the ones ticked, or every job (nil) when they all
  # are. None ticked would leave nobody anything to be, so that's every job
  # too. The boxes say it, whatever "Every job" was left at.
  def posted_open_jobs
    ticked = Array(params.dig(:campaign, :open_jobs)).compact_blank
    ticked.presence unless (@world.jobs.pluck(:slug) - ticked).empty?
  end

  def set_campaign
    @campaign = Campaign.find(params[:id])
    @world = @campaign.world
  end
end
