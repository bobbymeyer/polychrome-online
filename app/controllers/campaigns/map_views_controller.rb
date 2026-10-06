# frozen_string_literal: true

# The stage's map view (Campaign::Mapping). GET: the table's map frame with
# a map this viewer asked to look at (browsing alone; players see only what's
# revealed). PATCH (the GM's): put a map on the stage for everyone, or
# take the map off it (off=1).
class Campaigns::MapViewsController < Campaigns::BaseController
  def show
    seat = table_seat
    map = @campaign.maps.find(params[:map])
    render partial: "campaigns/tables/map", locals: { campaign: @campaign, gm: seat.gm?, browsing: map }
  end

  before_action :require_table_gm, only: :update

  def update
    if params[:off].present?
      @campaign.show_place!
    else
      @campaign.show_map!(params[:map].present? ? @campaign.maps.find(params[:map]) : @campaign.map_shown)
    end
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
