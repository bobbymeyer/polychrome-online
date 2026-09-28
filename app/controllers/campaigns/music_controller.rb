# frozen_string_literal: true

# The GM's choice of music for the table: a scene's track, silence, or
# nothing chosen (each page plays its own scene). Every game page of the
# campaign follows the change (Campaign#broadcast_music).
class Campaigns::MusicController < ApplicationController
  include CampaignScoped

  before_action :set_campaign
  before_action :require_campaign_gm

  def update
    @campaign.update!(music: params[:music].presence_in(Campaign::MUSIC_CHOICES))
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
