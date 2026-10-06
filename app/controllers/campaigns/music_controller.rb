# frozen_string_literal: true

# The GM's choice of music for the table, from the stage: a kind of scene's
# track, one of the world's tracks by name ("track:12"), silence, or nothing
# chosen (each page plays its own scene). Every game page of the campaign
# follows the change (Campaign#broadcast_music).
class Campaigns::MusicController < ApplicationController
  include CampaignScoped

  before_action :set_campaign
  before_action :require_campaign_gm

  def update
    choice = params[:music].to_s
    choice = nil unless Campaign::MUSIC_CHOICES.include?(choice) || @campaign.world.tracks.exists?(id: choice.delete_prefix("track:").to_i)
    @campaign.update!(music: choice)
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
