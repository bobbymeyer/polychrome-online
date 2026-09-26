# frozen_string_literal: true

class CampaignsController < ApplicationController
  include TableSeat

  before_action :set_campaign, only: %i[show edit update]

  def new
    @world = World.find_by!(slug: params[:world_slug])
    @campaign = @world.campaigns.new
  end

  def create
    @world = World.find_by!(slug: params[:world_slug])
    @campaign = @world.campaigns.new(params.expect(campaign: %i[name]))
    if @campaign.save
      redirect_to @campaign, notice: "#{@campaign.name} begins."
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    @characters = @campaign.characters.includes(:job, :character_jobs, equipment_slots: :item).order(:created_at)
    @battles = @campaign.battles.order(created_at: :desc).limit(10)
  end

  def edit; end

  def update
    if @campaign.update(params.expect(campaign: %i[name gil]))
      redirect_to @campaign, notice: "#{@campaign.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_campaign
    @campaign = Campaign.find(params[:id])
    @world = @campaign.world
  end
end
