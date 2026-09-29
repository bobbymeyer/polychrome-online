# frozen_string_literal: true

class NpcsController < ApplicationController
  include CampaignScoped
  include PortraitUploads

  before_action :set_campaign, only: %i[new create]
  before_action :set_npc, only: %i[edit update destroy]
  before_action :require_campaign_gm

  def new
    @npc = @campaign.npcs.new
  end

  def create
    @npc = @campaign.npcs.new(npc_params)
    if @npc.save
      @npc.update_portraits!(**portrait_params)
      redirect_to campaign_path(@campaign), notice: "#{@npc.name} joins the cast.", status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @npc.update(npc_params)
      @npc.update_portraits!(**portrait_params)
      redirect_to campaign_path(@campaign), notice: "#{@npc.name} was updated.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @npc.destroy!
    redirect_to campaign_path(@campaign), notice: "#{@npc.name} left the cast. Their lines stay, as the narrator's.",
                                          status: :see_other
  end

  private

  def set_npc
    @npc = Npc.find(params[:id])
    @campaign = @npc.campaign
    @world = @campaign.world
  end

  # Where they are: one of this campaign's places, or nowhere in particular.
  def npc_params
    attrs = params.expect(npc: %i[name title description colour monster_id location_id])
    return attrs unless attrs.key?(:location_id)

    attrs.merge(location_id: @campaign.locations.find_by(id: attrs[:location_id])&.id)
  end
end
