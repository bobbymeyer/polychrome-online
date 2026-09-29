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
      # The setting's places, people and trouble (its fronts), unless the GM
      # starts from nothing; then the party sets out from its first town.
      unless params[:blank_map] == "1"
        Atlas.new(@campaign).bring_in_all!
        WorldFront.undealt_in(@campaign).each { |front| front.deal!(@campaign) }
      end
      @campaign.set_out!
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

  # The form's job boxes: every job (nil), or the ones ticked. None ticked
  # would leave nobody anything to be, so that's every job too.
  def posted_open_jobs
    return if params.dig(:campaign, :every_job) == "1"

    Array(params.dig(:campaign, :open_jobs)).compact_blank.presence
  end

  def set_campaign
    @campaign = Campaign.find(params[:id])
    @world = @campaign.world
  end
end
