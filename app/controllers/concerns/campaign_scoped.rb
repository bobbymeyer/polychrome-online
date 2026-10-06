# frozen_string_literal: true

# Loads the campaign (and its world, for the book navigation) from a nested
# campaign route, or from the character, scene or beat the route names.
module CampaignScoped
  extend ActiveSupport::Concern

  private

  def set_campaign
    @campaign = Campaign.find(params[:campaign_id])
    @world = @campaign.world
  end

  def set_character
    @character = Character.find(params[:character_id] || params[:id])
    @campaign = @character.campaign
    @world = @campaign.world
  end

  def set_scene
    @scene = Scene.find(params[:scene_id] || params[:id])
    @campaign = @scene.campaign
    @world = @campaign.world
  end

  def set_beat
    @beat = Beat.find(params[:beat_id] || params[:id])
    @scene = @beat.scene
    @campaign = @scene.campaign
    @world = @campaign.world
  end

  # Re-render the character sheet with an error, for the sheet's forms.
  def sheet_error(message)
    redirect_to character_path(@character), alert: message, status: :see_other
  end
end
