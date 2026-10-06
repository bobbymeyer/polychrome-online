# frozen_string_literal: true

# A picture for one of a place's modes (ModeArt), uploaded by the GM: while
# the mode lasts, the table sees it instead of the Gazetteer entry's.
class Locations::ModeArtsController < ApplicationController
  include LocationScoped

  before_action :require_table_gm
  before_action :set_mode

  def update
    image = params.expect(mode_art: [ :image ])[:image]
    @location.mode_arts.find_or_create_by!(mode: @mode).image.attach(image)
    @campaign.table_changed
    back "#{@mode.name} has its picture.", anchor: "mode-pictures"
  end

  def destroy
    @location.mode_arts.find_by(mode: @mode)&.destroy!
    @campaign.table_changed
    back "#{@mode.name} shows #{@location.location_template.name}'s picture again.", anchor: "mode-pictures"
  end

  private

  def set_mode
    @mode = @location.map_node&.modes&.find_by(key: params[:mode].to_s) or raise ActiveRecord::RecordNotFound
  end
end
